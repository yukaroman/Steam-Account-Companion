import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/core/security/account_integrity_exception.dart';
import 'package:steam_account_companion/core/security/aes_gcm_account_cipher.dart';
import 'package:steam_account_companion/core/security/at_rest_account_cipher.dart';
import 'package:steam_account_companion/core/security/master_key_service.dart';
import 'package:steam_account_companion/core/security/memory_encrypted_account_store.dart';
import 'package:steam_account_companion/core/security/memory_secure_storage.dart';
import 'package:steam_account_companion/features/accounts/data/demo_accounts_seed.dart';
import 'package:steam_account_companion/features/accounts/data/encrypted_accounts_repository.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_private_meta.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_profile.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_secrets.dart';
import 'package:steam_account_companion/features/authenticator/data/steam_guard_authenticator_service.dart';
import 'package:steam_account_companion/features/authenticator/domain/steam_guard_codec.dart';

void main() {
  late MemoryEncryptedAccountStore store;
  late AtRestAccountCipher cipher;
  late EncryptedAccountsRepository repository;

  setUp(() async {
    final storage = MemorySecureStorage();
    store = MemoryEncryptedAccountStore();
    cipher = AtRestAccountCipher(
      encryptAtRest: true,
      encrypted: AesGcmAccountCipher(
        masterKeyService: MasterKeyService(secureStorage: storage),
      ),
    );
    repository = EncryptedAccountsRepository(store: store, cipher: cipher);
  });

  test('upsert stores ciphertext and listProfiles hides secrets', () async {
    await repository.upsert(
      profile: const SteamAccountProfile(
        id: 'a1',
        nickname: 'Alpha',
        loginNameHint: 'aa••••',
        initials: 'A',
        avatarColorValue: 0xFF112233,
      ),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      ),
    );

    final profiles = await repository.listProfiles();
    expect(profiles, hasLength(1));
    expect(profiles.single.id, 'a1');
    expect(profiles.single.nickname, 'Alpha');

    final secrets = await repository.readSecrets('a1');
    expect(secrets, isNotNull);
    expect(secrets!.sharedSecret, isNotEmpty);
  });

  test('demo seed + authenticator produces known Steam Guard codes', () async {
    await DemoAccountsSeed.seed(repository);
    final secretsMap = await repository.loadSharedSecretsByAccountId();
    final auth = SteamGuardAuthenticatorService(
      sharedSecretsByAccountId: secretsMap,
    );

    final now = DateTime.fromMillisecondsSinceEpoch(
      1700000000 * 1000,
      isUtc: true,
    );
    expect(auth.codeFor(accountId: 'mock-primary', now: now), '6CMP4');
    expect(
      auth.codeFor(accountId: 'mock-primary', now: now),
      SteamGuardCodec.codeFromBase64SharedSecret(
        sharedSecretBase64: DemoSteamGuardSecrets.byAccountId['mock-primary']!,
        now: now,
      ),
    );
  });

  test('delete removes profile and secrets', () async {
    await repository.upsert(
      profile: const SteamAccountProfile(
        id: 'gone',
        nickname: 'Gone',
        loginNameHint: 'g',
        initials: 'G',
        avatarColorValue: 0xFF000000,
      ),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'MTIzNDU2Nzg5MGFiY2RlZg==',
      ),
    );
    await repository.delete('gone');
    expect(await repository.getProfile('gone'), isNull);
    expect(await repository.readSecrets('gone'), isNull);
  });

  test('default encryption keeps non-plaintext-looking blobs', () async {
    await repository.upsert(
      profile: const SteamAccountProfile(
        id: 'x',
        nickname: 'X',
        loginNameHint: 'x',
        initials: 'X',
        avatarColorValue: 0xFFABCDEF,
      ),
      privateMeta: const SteamAccountPrivateMeta(
        accountName: 'visible-name-should-not-appear-in-blob',
      ),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'dGVzdC1zaGFyZWQtc2VjcmV0ISE=',
      ),
    );

    final blob = await store.read('x');
    expect(blob, isNotNull);
    final asString = String.fromCharCodes(blob!);
    expect(
        asString.contains('visible-name-should-not-appear-in-blob'), isFalse);
    expect(asString.contains('sharedSecretB64'), isFalse);
    expect(repository.encryptAtRest, isTrue);
    expect(await repository.getProfile('x'), isNotNull);
    expect(await repository.readSecrets('x'), isNotNull);
  });

  test('swapping account blobs fails integrity checks for both keys', () async {
    await repository.upsert(
      profile: const SteamAccountProfile(
        id: 'acc-a',
        nickname: 'A',
        loginNameHint: 'a',
        initials: 'A',
        avatarColorValue: 0xFF0000AA,
      ),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'dGVzdC1zaGFyZWQtc2VjcmV0ISE=',
      ),
    );
    await repository.upsert(
      profile: const SteamAccountProfile(
        id: 'acc-b',
        nickname: 'B',
        loginNameHint: 'b',
        initials: 'B',
        avatarColorValue: 0xFF0000BB,
      ),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      ),
    );

    final blobA = await store.read('acc-a');
    final blobB = await store.read('acc-b');
    expect(blobA, isNotNull);
    expect(blobB, isNotNull);

    // Swap ciphertext under the opposite storage keys.
    await store.save(accountId: 'acc-a', encryptedPayload: blobB!);
    await store.save(accountId: 'acc-b', encryptedPayload: blobA!);

    expect(
      () => repository.getProfile('acc-a'),
      throwsA(isA<AccountIntegrityException>()),
    );
    expect(
      () => repository.getProfile('acc-b'),
      throwsA(isA<AccountIntegrityException>()),
    );
    expect(
      () => repository.readSecrets('acc-a'),
      throwsA(isA<AccountIntegrityException>()),
    );
  });

  test('disabling encryption rewrites blobs back to plain JSON', () async {
    await repository.upsert(
      profile: const SteamAccountProfile(
        id: 'y',
        nickname: 'Y',
        loginNameHint: 'y',
        initials: 'Y',
        avatarColorValue: 0xFF000001,
      ),
      privateMeta:
          const SteamAccountPrivateMeta(accountName: 'plain-after-disable'),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      ),
    );

    await repository.setEncryptAtRest(false);
    final blob = await store.read('y');
    expect(String.fromCharCodes(blob!).contains('plain-after-disable'), isTrue);
    expect(repository.encryptAtRest, isFalse);
  });

  test('re-enabling encryption re-wraps plain blobs', () async {
    await repository.setEncryptAtRest(false);
    await repository.upsert(
      profile: const SteamAccountProfile(
        id: 'z',
        nickname: 'Z',
        loginNameHint: 'z',
        initials: 'Z',
        avatarColorValue: 0xFF000002,
      ),
      privateMeta: const SteamAccountPrivateMeta(accountName: 'secret-name'),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'dGVzdC1zaGFyZWQtc2VjcmV0ISE=',
      ),
    );

    await repository.setEncryptAtRest(true);
    final blob = await store.read('z');
    expect(String.fromCharCodes(blob!).contains('secret-name'), isFalse);
    expect(await repository.readSecrets('z'), isNotNull);
  });

  test('private meta is readable via domain API not profile', () async {
    await repository.upsert(
      profile: const SteamAccountProfile(
        id: 'p',
        nickname: 'P',
        loginNameHint: 'p••••',
        initials: 'P',
        avatarColorValue: 0xFF111111,
      ),
      privateMeta: const SteamAccountPrivateMeta(
        deviceId: 'android:abcd',
        serialNumber: 'SN-1',
      ),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      ),
    );

    final profile = await repository.getProfile('p');
    expect(profile!.toJson().containsKey('deviceId'), isFalse);
    expect(profile.toJson().containsKey('serialNumber'), isFalse);

    final privateMeta = await repository.readPrivateMeta('p');
    expect(privateMeta!.deviceId, 'android:abcd');
    expect(privateMeta.serialNumber, 'SN-1');
  });
}
