import 'secure_storage.dart';

/// In-process [SecureStorage] for tests and local prototype wiring.
///
/// Not durable across process restarts and not hardware-backed.
class MemorySecureStorage implements SecureStorage {
  MemorySecureStorage([Map<String, String>? seed])
      : _values = Map<String, String>.from(seed ?? const {});

  final Map<String, String> _values;

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }
}
