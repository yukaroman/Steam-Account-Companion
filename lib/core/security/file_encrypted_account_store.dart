import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'encrypted_account_store.dart';

/// Thrown when on-disk account metadata cannot be trusted.
class AccountStoreIntegrityException implements Exception {
  const AccountStoreIntegrityException(this.code, [this.message]);

  final String code;
  final String? message;

  static const indexCorrupt = 'index_corrupt';

  @override
  String toString() =>
      'AccountStoreIntegrityException($code${message == null ? '' : ': $message'})';
}

/// Disk-backed [EncryptedAccountStore] with atomic writes and serialized ops.
///
/// Layout under [rootDirectory]:
/// ```text
/// index.json          // {"ids":["..."]}  — ids only, no secrets
/// blobs/<safeId>.bin  // raw ciphertext bytes
/// ```
class FileEncryptedAccountStore implements EncryptedAccountStore {
  FileEncryptedAccountStore({
    required Directory rootDirectory,
    bool rebuildIndexFromBlobsOnCorrupt = true,
  })  : _root = rootDirectory,
        _rebuildOnCorrupt = rebuildIndexFromBlobsOnCorrupt;

  final Directory _root;
  final bool _rebuildOnCorrupt;
  Future<void> _queue = Future.value();

  Directory get _blobsDir => Directory(p.join(_root.path, 'blobs'));
  File get _indexFile => File(p.join(_root.path, 'index.json'));

  /// Creates directories if missing and ensures a valid index exists.
  ///
  /// Also reconciles a *valid* index that drifted from blob files (crash between
  /// blob write and index update, or orphaned index entries).
  Future<void> ensureReady() => _serialized(() async {
        await _root.create(recursive: true);
        await _blobsDir.create(recursive: true);
        if (!await _indexFile.exists()) {
          // Prefer blobs as source of truth if any survived a prior crash.
          final fromBlobs = await _scanBlobIds();
          await _writeIndexAtomic(fromBlobs);
          return;
        }
        await _reconcileIndexWithBlobs();
      });

  @override
  Future<void> save({
    required String accountId,
    required List<int> encryptedPayload,
  }) =>
      _serialized(() async {
        await _ensureDirs();
        await _writeBytesAtomic(_blobFile(accountId), encryptedPayload);

        final ids = await _readIndexStrict();
        if (!ids.contains(accountId)) {
          ids.add(accountId);
          await _writeIndexAtomic(ids);
        }
      });

  @override
  Future<List<int>?> read(String accountId) => _serialized(() async {
        await _ensureDirs();
        final file = _blobFile(accountId);
        if (!await file.exists()) return null;
        final bytes = await file.readAsBytes();
        return Uint8List.fromList(bytes);
      });

  @override
  Future<void> delete(String accountId) => _serialized(() async {
        await _ensureDirs();
        final file = _blobFile(accountId);
        if (await file.exists()) {
          await file.delete();
        }
        final ids = await _readIndexStrict();
        ids.remove(accountId);
        await _writeIndexAtomic(ids);
      });

  @override
  Future<List<String>> listAccountIds() => _serialized(() async {
        await _ensureDirs();
        final ids = await _reconcileIndexWithBlobs();
        return List<String>.unmodifiable(ids);
      });

  /// Rebuilds index.json purely from blob filenames (recovery helper).
  Future<List<String>> rebuildIndexFromBlobs() => _serialized(() async {
        await _ensureDirs();
        final ids = await _scanBlobIds();
        await _writeIndexAtomic(ids);
        return List<String>.unmodifiable(ids);
      });

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> _ensureDirs() async {
    await _root.create(recursive: true);
    await _blobsDir.create(recursive: true);
  }

  File _blobFile(String accountId) {
    final safe = _safeFileName(accountId);
    return File(p.join(_blobsDir.path, '$safe.bin'));
  }

  static String _safeFileName(String accountId) =>
      base64Url.encode(utf8.encode(accountId)).replaceAll('=', '');

  Future<List<String>> _readIndexStrict() async {
    if (!await _indexFile.exists()) {
      return [];
    }
    try {
      final raw = await _indexFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('index root is not an object');
      }
      final ids = decoded['ids'];
      if (ids is! List) {
        throw const FormatException('index ids is not a list');
      }
      return [
        for (final id in ids)
          if (id != null && id.toString().isNotEmpty) id.toString(),
      ];
    } on FormatException catch (error) {
      if (_rebuildOnCorrupt) {
        final rebuilt = await _scanBlobIds();
        await _writeIndexAtomic(rebuilt);
        return rebuilt;
      }
      throw AccountStoreIntegrityException(
        AccountStoreIntegrityException.indexCorrupt,
        error.message,
      );
    }
  }

  Future<List<String>> _scanBlobIds() async {
    if (!await _blobsDir.exists()) return [];
    final ids = <String>[];
    await for (final entity in _blobsDir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.bin')) continue;
      // Ignore in-progress atomic temp files (*.bin.tmp.<ts>).
      final base = p.basename(entity.path);
      if (base.contains('.tmp.')) continue;
      final name = p.basenameWithoutExtension(entity.path);
      try {
        final padded =
            name.padRight(name.length + (4 - name.length % 4) % 4, '=');
        final id = utf8.decode(base64Url.decode(padded));
        if (id.isNotEmpty) ids.add(id);
      } on FormatException {
        // Skip unmapped garbage files.
      }
    }
    ids.sort();
    return ids;
  }

  /// Keeps index.json aligned with blobs/ so crash mid-save cannot hide accounts.
  ///
  /// Blob files are the source of truth for *existence*. Index order is preserved
  /// when possible; missing blob ids are dropped; blob-only ids are appended.
  Future<List<String>> _reconcileIndexWithBlobs() async {
    final indexIds = await _readIndexStrict();
    final blobIds = await _scanBlobIds();
    final blobSet = blobIds.toSet();

    final reconciled = <String>[
      for (final id in indexIds)
        if (blobSet.contains(id)) id,
    ];
    final known = reconciled.toSet();
    for (final id in blobIds) {
      if (known.add(id)) reconciled.add(id);
    }

    final same = reconciled.length == indexIds.length &&
        reconciled.length == blobIds.length &&
        _listEquals(reconciled, indexIds);
    if (!same) {
      await _writeIndexAtomic(reconciled);
    }
    return reconciled;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _writeIndexAtomic(List<String> ids) async {
    final payload = utf8.encode(jsonEncode({'ids': ids}));
    await _writeBytesAtomic(_indexFile, payload);
  }

  Future<void> _writeBytesAtomic(File target, List<int> bytes) async {
    final temp =
        File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    await temp.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      await temp.rename(target.path);
    } else {
      // On some platforms rename-over may require delete first; try rename, fall back.
      try {
        await temp.rename(target.path);
      } on FileSystemException {
        await target.writeAsBytes(bytes, flush: true);
        if (await temp.exists()) await temp.delete();
      }
    }
  }
}
