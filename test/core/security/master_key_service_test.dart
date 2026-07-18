import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/core/security/aes_gcm_account_cipher.dart';
import 'package:steam_account_companion/core/security/master_key_service.dart';
import 'package:steam_account_companion/core/security/memory_secure_storage.dart';
import 'package:steam_account_companion/core/security/secure_storage.dart';

/// Test double that fails the first [failReads] reads, then delegates to memory.
class _FlakySecureStorage implements SecureStorage {
  _FlakySecureStorage({this.failReads = 0, this.failWrites = 0});

  final MemorySecureStorage _inner = MemorySecureStorage();
  int failReads;
  int failWrites;

  @override
  Future<String?> read(String key) async {
    if (failReads > 0) {
      failReads -= 1;
      throw StateError('simulated secure-storage read failure');
    }
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites > 0) {
      failWrites -= 1;
      throw StateError('simulated secure-storage write failure');
    }
    return _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);

  @override
  Future<void> deleteAll() => _inner.deleteAll();
}

void main() {
  test('concurrent getOrCreateMasterKey returns the same key material',
      () async {
    final storage = MemorySecureStorage();
    final keyService = MasterKeyService(secureStorage: storage);

    final results = await Future.wait([
      keyService.getOrCreateMasterKey(),
      keyService.getOrCreateMasterKey(),
      keyService.getOrCreateMasterKey(),
    ]);

    expect(results[1], results[0]);
    expect(results[2], results[0]);
    expect(results[0].length, MasterKeyService.keyLengthBytes);

    // Only one key persisted.
    final stored = await storage.read(MasterKeyService.defaultStorageKey);
    expect(stored, isNotNull);
    expect(base64.decode(stored!), results[0]);
  });

  test('returns defensive copies so callers cannot mutate the cache', () async {
    final keyService = MasterKeyService(secureStorage: MemorySecureStorage());
    final a = await keyService.getOrCreateMasterKey();
    a[0] = a[0] ^ 0xff;
    final b = await keyService.getOrCreateMasterKey();
    expect(b[0], isNot(a[0]));
  });

  test('concurrent encrypt then fresh service decrypts all blobs', () async {
    final storage = MemorySecureStorage();
    final keys = MasterKeyService(secureStorage: storage);
    final cipher = AesGcmAccountCipher(masterKeyService: keys);

    final plaintexts = {
      for (var i = 0; i < 8; i++) 'acc-$i': utf8.encode('payload-$i'),
    };

    final ciphertexts = await Future.wait([
      for (final entry in plaintexts.entries)
        cipher.encrypt(entry.value, accountId: entry.key),
    ]);

    // New service instance, same secure storage — must recover one master key.
    final keys2 = MasterKeyService(secureStorage: storage);
    final cipher2 = AesGcmAccountCipher(masterKeyService: keys2);

    for (var i = 0; i < ciphertexts.length; i++) {
      final accountId = 'acc-$i';
      final restored = await cipher2.decrypt(
        ciphertexts[i],
        accountId: accountId,
      );
      expect(restored, plaintexts[accountId]);
    }
  });

  test('failed init does not poison later retries', () async {
    final storage = _FlakySecureStorage(failReads: 1);
    final keyService = MasterKeyService(secureStorage: storage);

    await expectLater(
      keyService.getOrCreateMasterKey(),
      throwsA(isA<StateError>()),
    );

    // Storage is healthy again — must succeed without process restart.
    final key = await keyService.getOrCreateMasterKey();
    expect(key.length, MasterKeyService.keyLengthBytes);

    final again = await Future.wait([
      keyService.getOrCreateMasterKey(),
      keyService.getOrCreateMasterKey(),
    ]);
    expect(again[0], key);
    expect(again[1], key);
  });

  test('failed write can be retried after storage recovers', () async {
    final storage = _FlakySecureStorage(failWrites: 1);
    final keyService = MasterKeyService(secureStorage: storage);

    await expectLater(
      keyService.getOrCreateMasterKey(),
      throwsA(isA<StateError>()),
    );

    final key = await keyService.getOrCreateMasterKey();
    expect(key.length, MasterKeyService.keyLengthBytes);
    expect(
      await storage.read(MasterKeyService.defaultStorageKey),
      isNotNull,
    );
  });
}
