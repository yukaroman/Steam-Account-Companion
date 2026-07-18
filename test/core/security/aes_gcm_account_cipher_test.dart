import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/core/security/account_integrity_exception.dart';
import 'package:steam_account_companion/core/security/aes_gcm_account_cipher.dart';
import 'package:steam_account_companion/core/security/master_key_service.dart';
import 'package:steam_account_companion/core/security/memory_secure_storage.dart';

void main() {
  AesGcmAccountCipher buildCipher([MemorySecureStorage? storage]) {
    return AesGcmAccountCipher(
      masterKeyService: MasterKeyService(
        secureStorage: storage ?? MemorySecureStorage(),
      ),
    );
  }

  test('encrypt then decrypt restores plaintext for matching accountId',
      () async {
    final cipher = buildCipher();
    final plaintext = utf8.encode('{"hello":"steam"}');
    final ciphertext = await cipher.encrypt(plaintext, accountId: 'acc-a');
    final restored = await cipher.decrypt(ciphertext, accountId: 'acc-a');

    expect(restored, plaintext);
    expect(ciphertext, isNot(equals(plaintext)));
    expect(ciphertext.first, AesGcmAccountCipher.formatVersion);
  });

  test('ciphertext differs across encrypt calls (unique nonces)', () async {
    final cipher = buildCipher();
    final plaintext = utf8.encode('same-payload');
    final a = await cipher.encrypt(plaintext, accountId: 'acc');
    final b = await cipher.encrypt(plaintext, accountId: 'acc');
    expect(a, isNot(equals(b)));
  });

  test('wrong accountId AAD fails authentication', () async {
    final cipher = buildCipher();
    final ciphertext = await cipher.encrypt(
      utf8.encode('secret-account'),
      accountId: 'acc-a',
    );

    expect(
      () => cipher.decrypt(ciphertext, accountId: 'acc-b'),
      throwsA(
        isA<AccountIntegrityException>().having(
          (e) => e.code,
          'code',
          AccountIntegrityException.swappedOrTampered,
        ),
      ),
    );
  });

  test('tampered nonce, mac, body, or version fail decrypt', () async {
    final cipher = buildCipher();
    final original = await cipher.encrypt(
      utf8.encode('secret-account'),
      accountId: 'acc',
    );

    Future<void> expectFail(List<int> mutated) async {
      expect(
        () => cipher.decrypt(mutated, accountId: 'acc'),
        throwsA(isA<AccountIntegrityException>()),
      );
    }

    final nonceFlip = List<int>.from(original)..[2] ^= 0x01;
    final macFlip = List<int>.from(original)
      ..[1 + AesGcmAccountCipher.nonceLength] ^= 0x01;
    final bodyFlip = List<int>.from(original)..[original.length - 1] ^= 0x01;
    final versionFlip = List<int>.from(original)..[0] = 9;

    await expectFail(nonceFlip);
    await expectFail(macFlip);
    await expectFail(bodyFlip);
    await expectFail(versionFlip);
  });

  test('master key is reused from secure storage', () async {
    final storage = MemorySecureStorage();
    final first = MasterKeyService(secureStorage: storage);
    final keyA = await first.getOrCreateMasterKey();
    first.clearCache();

    final second = MasterKeyService(secureStorage: storage);
    final keyB = await second.getOrCreateMasterKey();
    expect(keyB, keyA);
  });
}
