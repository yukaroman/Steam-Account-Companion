import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage.dart';

/// [SecureStorage] backed by platform Keychain / Keystore / OS secure storage.
class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // Prefer platform defaults; accessibility tuned for device unlock.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
