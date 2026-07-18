import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/core/security/aes_gcm_account_cipher.dart';
import 'package:steam_account_companion/core/security/at_rest_account_cipher.dart';
import 'package:steam_account_companion/core/security/master_key_service.dart';
import 'package:steam_account_companion/core/security/memory_encrypted_account_store.dart';
import 'package:steam_account_companion/core/security/memory_secure_storage.dart';
import 'package:steam_account_companion/features/accounts/data/encrypted_accounts_repository.dart';
import 'package:steam_account_companion/features/authenticator/data/steam_guard_authenticator_service.dart';
import 'package:steam_account_companion/features/authenticator/domain/steam_guard_codec.dart';
import 'package:steam_account_companion/app/app_services.dart';
import 'package:steam_account_companion/features/import/domain/account_importer.dart';

void main() {
  late EncryptedAccountsRepository repository;
  late AccountImporter importer;

  setUp(() {
    final cipher = AtRestAccountCipher(
      encrypted: AesGcmAccountCipher(
        masterKeyService:
            MasterKeyService(secureStorage: MemorySecureStorage()),
      ),
    );
    repository = EncryptedAccountsRepository(
      store: MemoryEncryptedAccountStore(),
      cipher: cipher,
    );
    importer = AccountImporter(repository: repository);
  });

  test('imports sanitized maFile into encrypted repository', () async {
    final source = File('test/fixtures/mafile/sample_sanitized.maFile.json')
        .readAsStringSync();

    final result = await importer.importJsonString(
      source,
      sourceLabel: 'sample_sanitized.maFile.json',
    );

    expect(result.successCount, 1);
    expect(result.failures, isEmpty);
    expect(result.importedAccountIds.single, 'steam:76561198000000001');

    final profiles = await repository.listProfiles();
    expect(profiles, hasLength(1));
    expect(profiles.single.nickname, 'demo_import');
    expect(profiles.single.loginNameHint, 'demo_import');
    expect(profiles.single.toJson().containsKey('deviceId'), isFalse);

    final privateMeta = await repository.readPrivateMeta(profiles.single.id);
    expect(privateMeta!.deviceId, startsWith('android:'));
    expect(privateMeta.steamId64, '76561198000000001');

    final secrets = await repository.readSecrets(profiles.single.id);
    expect(secrets, isNotNull);

    final code = SteamGuardCodec.codeFromSharedSecret(
      sharedSecret: secrets!.sharedSecret,
      now: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );
    expect(code, '6CMP4');
  });

  test('imports lightweight steam_username export with password', () async {
    const source = '''
{
  "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
  "identity_secret": "aWRlbnRpdHktc2VjcmV0LTE=",
  "steam_username": "demo__login__name",
  "steam_password": "demo-pass-not-real",
  "tool_extra": true
}
''';
    final result = await importer.importJsonString(source);
    expect(result.successCount, 1);
    expect(result.failures, isEmpty);
    expect(result.importedDisplayNames.single, 'demo__login__name');

    final profiles = await repository.listProfiles();
    expect(profiles.single.nickname, 'demo__login__name');
    expect(profiles.single.loginNameHint, 'demo__login__name');
    expect(profiles.single.initials, 'DL');
    expect(result.importedAccountIds.single, 'name:demo__login__name');

    final secrets = await repository.readSecrets(profiles.single.id);
    expect(secrets!.steamPassword, 'demo-pass-not-real');
    expect(secrets.identitySecret, isNotNull);
  });

  test('import failure does not create accounts', () async {
    final result = await importer.importJsonString('{"nope":true}');
    expect(result.successCount, 0);
    expect(result.failures, isNotEmpty);
    expect(await repository.listProfiles(), isEmpty);
  });

  test('re-import same steam id upserts instead of duplicating', () async {
    final source = File('test/fixtures/mafile/sample_sanitized.maFile.json')
        .readAsStringSync();
    await importer.importJsonString(source);
    await importer.importJsonString(source);
    expect(await repository.listProfiles(), hasLength(1));
  });

  test('AppServices import reloads authenticator secrets', () async {
    // Local wiring mirroring AppServices secret reload.
    final secretsBefore = await repository.loadSharedSecretsByAccountId();
    expect(secretsBefore, isEmpty);

    final source = File('test/fixtures/mafile/sample_sanitized.maFile.json')
        .readAsStringSync();
    await importer.importJsonString(source);

    final secrets = await repository.loadSharedSecretsByAccountId();
    final auth = SteamGuardAuthenticatorService(
      sharedSecretsByAccountId: secrets,
    );
    final now = DateTime.fromMillisecondsSinceEpoch(
      1700000000 * 1000,
      isUtc: true,
    );
    expect(
      auth.codeFor(accountId: 'steam:76561198000000001', now: now),
      '6CMP4',
    );
  });

  test('imports SteamTools accounts map with uuid_key as device id', () async {
    final services = await AppServices.createInMemory(
      seedDemoAccounts: false,
      syncServerTimeOnStart: false,
    );
    const source = '''
{
  "accounts": {
    "76561198000000001": {
      "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
      "identity_secret": "aWRlbnRpdHktc2VjcmV0LTE=",
      "account_name": "map_import_user",
      "steamid": "76561198000000001"
    }
  },
  "uuid_key": "android:b656a73f-57ee-482c-a72b-a186edd1072b"
}
''';
    final result = await services.importMaFileJson(source);
    expect(result.successCount, 1);
    final id = result.importedAccountIds.single;
    final meta = await services.accountsRepository.readPrivateMeta(id);
    expect(meta?.steamId64, '76561198000000001');
    expect(meta?.deviceId, 'android:b656a73f-57ee-482c-a72b-a186edd1072b');
    final details = await services.loadAccountDetails(id);
    expect(details?.hasIdentitySecret, isTrue);
    expect(details?.hasMobileSession, isFalse);
  });
}
