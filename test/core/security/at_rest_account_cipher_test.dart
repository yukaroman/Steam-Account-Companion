import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/core/security/aes_gcm_account_cipher.dart';
import 'package:steam_account_companion/core/security/at_rest_account_cipher.dart';
import 'package:steam_account_companion/core/security/master_key_service.dart';
import 'package:steam_account_companion/core/security/memory_secure_storage.dart';

void main() {
  AtRestAccountCipher buildCipher({bool encryptAtRest = true}) {
    return AtRestAccountCipher(
      encryptAtRest: encryptAtRest,
      encrypted: AesGcmAccountCipher(
        masterKeyService:
            MasterKeyService(secureStorage: MemorySecureStorage()),
      ),
    );
  }

  test('default mode produces non-JSON AES-GCM blobs', () async {
    final cipher = buildCipher();
    expect(cipher.encryptAtRest, isTrue);

    final plaintext = utf8.encode('{"schemaVersion":1}');
    final stored = await cipher.encrypt(plaintext, accountId: 'a');
    expect(stored.first, AesGcmAccountCipher.formatVersion);
    expect(String.fromCharCodes(stored).contains('schemaVersion'), isFalse);
    expect(await cipher.decrypt(stored, accountId: 'a'), plaintext);
  });

  test('opt-out mode stores plain UTF-8 JSON', () async {
    final cipher = buildCipher(encryptAtRest: false);
    final plaintext = utf8.encode('{"schemaVersion":1}');
    final stored = await cipher.encrypt(plaintext, accountId: 'a');
    expect(utf8.decode(stored), '{"schemaVersion":1}');
    expect(await cipher.decrypt(stored, accountId: 'a'), plaintext);
  });

  test('decrypt still reads plain blobs after encryption is turned on',
      () async {
    final cipher = buildCipher(encryptAtRest: false);
    final plaintext = utf8.encode('{"id":"a"}');
    final plainBlob = await cipher.encrypt(plaintext, accountId: 'a');

    cipher.encryptAtRest = true;
    expect(await cipher.decrypt(plainBlob, accountId: 'a'), plaintext);
  });
}
