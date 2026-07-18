import 'flutter_secure_storage_adapter.dart';
import 'memory_secure_storage.dart';
import 'secure_storage.dart';

/// Platform Keychain/Keystore-backed storage adapter.
///
/// Defaults to [FlutterSecureStorageAdapter]. Tests may inject
/// [MemorySecureStorage] via [delegate].
class PlatformSecureStorage implements SecureStorage {
  PlatformSecureStorage({SecureStorage? delegate})
      : _delegate = delegate ?? FlutterSecureStorageAdapter();

  /// Explicit device-backed storage (Keychain / Keystore).
  factory PlatformSecureStorage.device() =>
      PlatformSecureStorage(delegate: FlutterSecureStorageAdapter());

  /// In-process only (tests / ephemeral sessions).
  factory PlatformSecureStorage.memory([Map<String, String>? seed]) =>
      PlatformSecureStorage(delegate: MemorySecureStorage(seed));

  final SecureStorage _delegate;

  @override
  Future<void> write(String key, String value) => _delegate.write(key, value);

  @override
  Future<String?> read(String key) => _delegate.read(key);

  @override
  Future<void> delete(String key) => _delegate.delete(key);

  @override
  Future<void> deleteAll() => _delegate.deleteAll();
}
