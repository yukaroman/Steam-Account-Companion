import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_profile.dart';

void main() {
  test('presentation profile JSON has no sensitive identity fields', () {
    const profile = SteamAccountProfile(
      id: 'internal-id',
      nickname: 'Primary',
      loginNameHint: 'ku•••••o',
      initials: 'P',
      avatarColorValue: 0xFF6B8CFF,
    );

    final keys = profile.toJson().keys.toSet();
    expect(keys, {
      'id',
      'nickname',
      'loginNameHint',
      'initials',
      'avatarColorValue',
    });

    const forbidden = {
      'sharedSecret',
      'sharedSecretB64',
      'identitySecret',
      'identitySecretB64',
      'revocationCode',
      'deviceId',
      'serialNumber',
      'accountName',
      'steamId64',
      'cookie',
      'token',
      'accessToken',
      'refreshToken',
      'sessionId',
    };
    expect(keys.intersection(forbidden), isEmpty);
  });

  test('presentation sources do not import secrets or private meta types', () {
    const presentationFiles = [
      'lib/features/authenticator/presentation/token_page.dart',
      'lib/features/confirmations/presentation/confirmations_page.dart',
      'lib/features/settings/presentation/settings_page.dart',
      'lib/features/lock/presentation/unlock_page.dart',
      'lib/app/home_shell.dart',
    ];

    final bannedSnippets = [
      'steam_account_secrets',
      'SteamAccountSecrets',
      'steam_account_private_meta',
      'SteamAccountPrivateMeta',
      'steam_account_payload',
      'SteamAccountPayload',
      'shared_secret',
      'identity_secret',
    ];

    for (final path in presentationFiles) {
      final source = File(path).readAsStringSync();
      for (final banned in bannedSnippets) {
        expect(
          source.contains(banned),
          isFalse,
          reason: '$path must not reference $banned',
        );
      }
    }
  });
}
