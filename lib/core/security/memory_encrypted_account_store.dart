import 'dart:typed_data';

import 'encrypted_account_store.dart';

/// In-memory [EncryptedAccountStore] for tests and prototype sessions.
class MemoryEncryptedAccountStore implements EncryptedAccountStore {
  MemoryEncryptedAccountStore([Map<String, List<int>>? seed])
      : _blobs = {
          for (final entry in (seed ?? const <String, List<int>>{}).entries)
            entry.key: Uint8List.fromList(entry.value),
        };

  final Map<String, Uint8List> _blobs;

  @override
  Future<void> save({
    required String accountId,
    required List<int> encryptedPayload,
  }) async {
    _blobs[accountId] = Uint8List.fromList(encryptedPayload);
  }

  @override
  Future<List<int>?> read(String accountId) async {
    final blob = _blobs[accountId];
    return blob == null ? null : Uint8List.fromList(blob);
  }

  @override
  Future<void> delete(String accountId) async {
    _blobs.remove(accountId);
  }

  @override
  Future<List<String>> listAccountIds() async =>
      _blobs.keys.toList(growable: false);
}
