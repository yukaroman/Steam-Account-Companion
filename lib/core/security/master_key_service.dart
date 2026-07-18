import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'secure_storage.dart';

/// Creates and loads the AES-256 master key from [SecureStorage].
///
/// The master key never leaves this service except as raw key bytes for the
/// account cipher. Callers always receive a defensive copy. Concurrent
/// [getOrCreateMasterKey] calls share a single in-flight initialization
/// future so two keys cannot be minted for the same storage slot.
///
/// If initialization fails, the in-flight future is cleared so a later call
/// can retry (e.g. after transient Keychain errors).
class MasterKeyService {
  MasterKeyService({
    required SecureStorage secureStorage,
    Random? random,
    this.storageKey = defaultStorageKey,
  })  : _secureStorage = secureStorage,
        _random = random ?? Random.secure();

  static const defaultStorageKey = 'account_master_key_v1';
  static const keyLengthBytes = 32;

  final SecureStorage _secureStorage;
  final Random _random;
  final String storageKey;

  Uint8List? _cachedKey;
  Future<Uint8List>? _initFuture;

  /// Returns the existing master key or generates a new one.
  ///
  /// Concurrent callers await the same initialization future. Failures do not
  /// permanently poison the service — the next call may retry.
  Future<Uint8List> getOrCreateMasterKey() {
    final cached = _cachedKey;
    if (cached != null) {
      return Future<Uint8List>.value(Uint8List.fromList(cached));
    }

    return _initFuture ??= _initialize();
  }

  Future<Uint8List> _initialize() async {
    try {
      final key = await _loadOrCreate();
      _cachedKey = key;
      return Uint8List.fromList(key);
    } finally {
      // Clear whether success or failure so retries remain possible after errors.
      _initFuture = null;
    }
  }

  Future<Uint8List> _loadOrCreate() async {
    final existing = await _secureStorage.read(storageKey);
    if (existing != null && existing.isNotEmpty) {
      final key = Uint8List.fromList(base64.decode(existing));
      if (key.length != keyLengthBytes) {
        throw StateError(
          'Master key in secure storage has invalid length ${key.length}',
        );
      }
      return key;
    }

    final key = _generateKey();
    await _secureStorage.write(storageKey, base64.encode(key));
    return key;
  }

  /// Drops the in-memory cache (does not delete Keychain material).
  void clearCache() {
    _cachedKey = null;
    _initFuture = null;
  }

  Future<void> deleteMasterKey() async {
    clearCache();
    await _secureStorage.delete(storageKey);
  }

  Uint8List _generateKey() {
    final bytes = Uint8List(keyLengthBytes);
    for (var i = 0; i < keyLengthBytes; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
