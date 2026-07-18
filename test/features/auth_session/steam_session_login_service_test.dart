import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/core/security/aes_gcm_account_cipher.dart';
import 'package:steam_account_companion/core/security/at_rest_account_cipher.dart';
import 'package:steam_account_companion/core/security/master_key_service.dart';
import 'package:steam_account_companion/core/security/memory_encrypted_account_store.dart';
import 'package:steam_account_companion/core/security/memory_secure_storage.dart';
import 'package:steam_account_companion/features/accounts/data/encrypted_accounts_repository.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_private_meta.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_profile.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_secrets.dart';
import 'package:steam_account_companion/features/auth_session/data/steam_login_client.dart';
import 'package:steam_account_companion/features/auth_session/domain/steam_login_result.dart';
import 'package:steam_account_companion/features/auth_session/domain/steam_session_login_service.dart';
import 'package:steam_account_companion/features/authenticator/domain/authenticator_service.dart';

class _FakeAuth implements AuthenticatorService {
  @override
  String codeFor({required String accountId, required DateTime now}) => 'ABCDE';

  @override
  int secondsRemaining(DateTime now) => 15;
}

class _FakeLoginClient extends SteamLoginClient {
  _FakeLoginClient(this.result);

  SteamLoginClientResult result;

  @override
  Future<SteamLoginClientResult> login({
    required String username,
    required String password,
    String? twoFactorCode,
    String? emailCode,
    bool rememberLogin = true,
  }) async {
    return result;
  }

  @override
  Future<SteamLoginClientResult> continueWithGuardCode({
    required int clientId,
    required List<int> requestId,
    required int steamId,
    required SteamLoginGuardKind kind,
    required String code,
  }) async {
    return result;
  }
}

void main() {
  test('persists access/refresh tokens on success', () async {
    final store = MemoryEncryptedAccountStore();
    final keys = MasterKeyService(secureStorage: MemorySecureStorage());
    final cipher = AtRestAccountCipher(
      encrypted: AesGcmAccountCipher(masterKeyService: keys),
      encryptAtRest: true,
    );
    final accounts = EncryptedAccountsRepository(store: store, cipher: cipher);

    const accountId = 'steam:76561198000000001';
    await accounts.upsert(
      profile: const SteamAccountProfile(
        id: accountId,
        nickname: 'demo',
        loginNameHint: 'demo',
        initials: 'D',
        avatarColorValue: 0xFF6B8CFF,
      ),
      privateMeta: const SteamAccountPrivateMeta(
        accountName: 'demo',
        steamId64: '76561198000000001',
        deviceId: 'android:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      ),
      secrets: SteamAccountSecrets(
        sharedSecret: Uint8List.fromList(utf8.encode('shared-secret!!')),
        identitySecret: Uint8List.fromList(utf8.encode('identity-secret')),
      ),
    );

    final loginClient = _FakeLoginClient(
      const SteamLoginSuccess(
        steamId64: '76561198000000001',
        accessToken: 'access-token-demo',
        refreshToken: 'refresh-token-demo',
      ),
    );

    final service = SteamSessionLoginService(
      accounts: accounts,
      authenticator: _FakeAuth(),
      loginClient: loginClient,
    );

    final outcome = await service.login(
      accountId: accountId,
      username: 'demo',
      password: 'secret',
      rememberPassword: true,
    );

    expect(outcome, isA<SteamSessionLoginOk>());
    final secrets = await accounts.readSecrets(accountId);
    expect(secrets?.accessToken, 'access-token-demo');
    expect(secrets?.refreshToken, 'refresh-token-demo');
    expect(secrets?.steamLoginSecure, contains('access-token-demo'));
    expect(
      secrets?.steamLoginSecure,
      '76561198000000001%7C%7Caccess-token-demo',
    );
    expect(secrets?.sessionId, isNotEmpty);
    expect(secrets?.steamPassword, 'secret');
    expect(secrets?.hasMobileSession, isTrue);
  });

  test('rejects session when SteamID does not match local meta', () async {
    final store = MemoryEncryptedAccountStore();
    final keys = MasterKeyService(secureStorage: MemorySecureStorage());
    final cipher = AtRestAccountCipher(
      encrypted: AesGcmAccountCipher(masterKeyService: keys),
      encryptAtRest: true,
    );
    final accounts = EncryptedAccountsRepository(store: store, cipher: cipher);

    const accountId = 'steam:76561198000000001';
    await accounts.upsert(
      profile: const SteamAccountProfile(
        id: accountId,
        nickname: 'demo',
        loginNameHint: 'demo',
        initials: 'D',
        avatarColorValue: 0xFF6B8CFF,
      ),
      privateMeta: const SteamAccountPrivateMeta(
        accountName: 'demo',
        steamId64: '76561198000000001',
        deviceId: 'android:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      ),
      secrets: SteamAccountSecrets(
        sharedSecret: Uint8List.fromList(utf8.encode('shared-secret!!')),
        identitySecret: Uint8List.fromList(utf8.encode('identity-secret')),
        steamPassword: 'old-password',
      ),
    );

    final loginClient = _FakeLoginClient(
      const SteamLoginSuccess(
        steamId64: '76561198000000099',
        accessToken: 'access-b',
        refreshToken: 'refresh-b',
      ),
    );

    final service = SteamSessionLoginService(
      accounts: accounts,
      authenticator: _FakeAuth(),
      loginClient: loginClient,
    );

    final outcome = await service.login(
      accountId: accountId,
      username: 'other',
      password: 'secret',
      rememberPassword: true,
    );

    expect(outcome, isA<SteamSessionLoginError>());
    expect((outcome as SteamSessionLoginError).code, 'account_mismatch');

    final secrets = await accounts.readSecrets(accountId);
    final meta = await accounts.readPrivateMeta(accountId);
    expect(secrets?.accessToken, isNull);
    expect(secrets?.refreshToken, isNull);
    expect(secrets?.steamLoginSecure, isNull);
    expect(secrets?.steamPassword, 'old-password');
    expect(meta?.steamId64, '76561198000000001');
  });

  test('unchecking remember password clears previously saved password',
      () async {
    final store = MemoryEncryptedAccountStore();
    final keys = MasterKeyService(secureStorage: MemorySecureStorage());
    final cipher = AtRestAccountCipher(
      encrypted: AesGcmAccountCipher(masterKeyService: keys),
      encryptAtRest: true,
    );
    final accounts = EncryptedAccountsRepository(store: store, cipher: cipher);

    const accountId = 'steam:76561198000000001';
    await accounts.upsert(
      profile: const SteamAccountProfile(
        id: accountId,
        nickname: 'demo',
        loginNameHint: 'demo',
        initials: 'D',
        avatarColorValue: 0xFF6B8CFF,
      ),
      privateMeta: const SteamAccountPrivateMeta(
        accountName: 'demo',
        steamId64: '76561198000000001',
      ),
      secrets: SteamAccountSecrets(
        sharedSecret: Uint8List.fromList(utf8.encode('shared-secret!!')),
        steamPassword: 'old-password',
      ),
    );

    final loginClient = _FakeLoginClient(
      const SteamLoginSuccess(
        steamId64: '76561198000000001',
        accessToken: 'access-token-demo',
        refreshToken: 'refresh-token-demo',
      ),
    );

    final service = SteamSessionLoginService(
      accounts: accounts,
      authenticator: _FakeAuth(),
      loginClient: loginClient,
    );

    final outcome = await service.login(
      accountId: accountId,
      username: 'demo',
      password: 'new-secret',
      rememberPassword: false,
    );

    expect(outcome, isA<SteamSessionLoginOk>());
    final secrets = await accounts.readSecrets(accountId);
    expect(secrets?.steamPassword, isNull);
    expect(secrets?.accessToken, 'access-token-demo');
  });
}
