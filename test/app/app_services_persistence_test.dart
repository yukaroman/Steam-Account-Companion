import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/app/app_services.dart';
import 'package:steam_account_companion/core/security/file_encrypted_account_store.dart';
import 'package:steam_account_companion/core/security/platform_secure_storage.dart';
import 'package:steam_account_companion/features/authenticator/domain/steam_guard_codec.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sac_services_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('startup purges leftover mock demo accounts when seed is off', () async {
    final secure = PlatformSecureStorage.memory();
    final store = FileEncryptedAccountStore(rootDirectory: tempDir);
    await store.ensureReady();

    final seeded = await AppServices.createPrototype(
      seedDemoAccounts: true,
      secureStorage: secure,
      accountStore: store,
      syncServerTimeOnStart: false,
    );
    expect(await seeded.accountsRepository.listProfiles(), isNotEmpty);

    final cleaned = await AppServices.createPrototype(
      seedDemoAccounts: false,
      secureStorage: secure,
      accountStore: FileEncryptedAccountStore(rootDirectory: tempDir),
      syncServerTimeOnStart: false,
    );
    expect(await cleaned.accountsRepository.listProfiles(), isEmpty);
  });

  test('imported account survives service rebuild with same storage', () async {
    final secure = PlatformSecureStorage.memory();
    final store = FileEncryptedAccountStore(rootDirectory: tempDir);
    await store.ensureReady();

    final first = await AppServices.createPrototype(
      seedDemoAccounts: false,
      secureStorage: secure,
      accountStore: store,
      syncServerTimeOnStart: false,
    );

    final source = File('test/fixtures/mafile/sample_sanitized.maFile.json')
        .readAsStringSync();
    final importResult = await first.importMaFileJson(source);
    expect(importResult.successCount, 1);

    final accountId = importResult.importedAccountIds.single;
    final now = DateTime.fromMillisecondsSinceEpoch(
      1700000000 * 1000,
      isUtc: true,
    );
    expect(
      first.authenticatorService.codeFor(accountId: accountId, now: now),
      '6CMP4',
    );

    // Simulate process restart: new AppServices, same key material + disk blobs.
    final second = await AppServices.createPrototype(
      seedDemoAccounts: false,
      secureStorage: secure,
      accountStore: FileEncryptedAccountStore(rootDirectory: tempDir),
      syncServerTimeOnStart: false,
    );

    final profiles = await second.accountsRepository.listProfiles();
    expect(profiles.map((p) => p.id), contains(accountId));
    expect(profiles, hasLength(1)); // no demo seed stacked on top

    expect(
      second.authenticatorService.codeFor(accountId: accountId, now: now),
      SteamGuardCodec.codeFromBase64SharedSecret(
        sharedSecretBase64: 'dGVzdC1zaGFyZWQtc2VjcmV0ISE=',
        now: now,
      ),
    );
  });
}
