import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/app/app_services.dart';
import 'package:steam_account_companion/core/security/account_backup_codec.dart';
import 'package:steam_account_companion/core/security/account_integrity_exception.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_payload.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_private_meta.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_profile.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_secrets.dart';

void main() {
  SteamAccountPayload sample(String id) {
    return SteamAccountPayload(
      profile: SteamAccountProfile(
        id: id,
        nickname: 'User $id',
        loginNameHint: 'user_$id',
        initials: 'U',
        avatarColorValue: 0xFF6B8CFF,
      ),
      privateMeta: SteamAccountPrivateMeta(
        accountName: 'user_$id',
        steamId64: '7656119800000000$id',
        deviceId: 'android:00000000-0000-4000-8000-00000000000$id',
      ),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'dGVzdC1zaGFyZWQtc2VjcmV0ISE=',
        identitySecretBase64: 'aWRlbnRpdHktc2VjcmV0LTE=',
        sessionId: 'sess_$id',
        steamLoginSecure: 'login_$id',
        accessToken: 'access_$id',
        refreshToken: 'refresh_$id',
      ),
    );
  }

  test('encrypt/decrypt backup roundtrip preserves accounts', () async {
    final accounts = [sample('1'), sample('2')];
    final file = await AccountBackupCodec.encryptBackup(
      accounts: accounts,
      password: 'correct-horse-battery',
    );

    final envelope = jsonDecode(utf8.decode(file)) as Map<String, Object?>;
    expect(envelope['format'], 'sacbak');
    expect(envelope['accountCount'], 2);
    expect(envelope['ciphertextB64'], isNotEmpty);

    final restored = await AccountBackupCodec.decryptBackup(
      fileBytes: file,
      password: 'correct-horse-battery',
    );
    expect(restored.accounts, hasLength(2));
    expect(restored.accounts.map((a) => a.profile.id), ['1', '2']);
    expect(restored.accounts.first.secrets.sessionId, 'sess_1');
    expect(restored.accounts.first.secrets.accessToken, 'access_1');
    expect(restored.accounts.first.secrets.refreshToken, 'refresh_1');
    expect(
      restored.accounts.first.secrets.steamLoginSecure,
      'login_1',
    );
  });

  test('wrong password fails closed', () async {
    final file = await AccountBackupCodec.encryptBackup(
      accounts: [sample('1')],
      password: 'correct-horse-battery',
    );

    expect(
      () => AccountBackupCodec.decryptBackup(
        fileBytes: file,
        password: 'wrong-password-xx',
      ),
      throwsA(isA<AccountIntegrityException>()),
    );
  });

  test('AppServices restore merges and keeps encrypt-at-rest preference',
      () async {
    final services = await AppServices.createInMemory(
      seedDemoAccounts: false,
      encryptAccountsAtRest: true,
      syncServerTimeOnStart: false,
    );
    expect(services.encryptAccountsAtRest, isTrue);

    final file = await AccountBackupCodec.encryptBackup(
      accounts: [sample('restored-a'), sample('restored-b')],
      password: 'backup-password-1',
    );

    final result = await services.restoreEncryptedBackup(
      fileBytes: file,
      password: 'backup-password-1',
    );
    expect(result.restoredCount, 2);
    expect(services.encryptAccountsAtRest, isTrue);

    final profiles = await services.accountsRepository.listProfiles();
    expect(profiles.map((p) => p.id).toSet(), {
      'restored-a',
      'restored-b',
    });

    // Second restore of a subset overwrites / merges.
    final file2 = await AccountBackupCodec.encryptBackup(
      accounts: [sample('restored-c')],
      password: 'backup-password-1',
    );
    await services.restoreEncryptedBackup(
      fileBytes: file2,
      password: 'backup-password-1',
    );
    final after = await services.accountsRepository.listProfiles();
    expect(after.map((p) => p.id).toSet(), {
      'restored-a',
      'restored-b',
      'restored-c',
    });
  });

  test('exportEncryptedBackup includes seeded demos', () async {
    final services = await AppServices.createInMemory(
      seedDemoAccounts: true,
      syncServerTimeOnStart: false,
    );
    final bytes = await services.exportEncryptedBackup(
      password: 'export-password-99',
    );
    final restored = await AccountBackupCodec.decryptBackup(
      fileBytes: bytes,
      password: 'export-password-99',
    );
    expect(restored.accounts, isNotEmpty);
    expect(
      restored.accounts.every((a) => a.profile.id.startsWith('mock-')),
      isTrue,
    );
  });
}
