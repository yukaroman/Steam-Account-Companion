import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/core/security/account_payload_codec.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_payload.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_private_meta.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_profile.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_secrets.dart';

void main() {
  test('round-trips profile, private meta, and secrets', () {
    final payload = SteamAccountPayload(
      profile: const SteamAccountProfile(
        id: 'acc-1',
        nickname: 'Primary',
        loginNameHint: 'ab•••••z',
        initials: 'P',
        avatarColorValue: 0xFF6B8CFF,
      ),
      privateMeta: const SteamAccountPrivateMeta(
        accountName: 'demo',
        steamId64: '76561198000000000',
        deviceId: 'android:11111111-1111-4111-8111-111111111111',
      ),
      secrets: SteamAccountSecrets.fromBase64(
        sharedSecretBase64: 'dGVzdC1zaGFyZWQtc2VjcmV0ISE=',
        identitySecretBase64: 'aWRlbnRpdHktc2VjcmV0LTE=',
        revocationCode: 'R12345',
      ),
    );

    final bytes = AccountPayloadCodec.encode(payload);
    final restored = AccountPayloadCodec.decode(bytes);

    expect(restored.profile.id, 'acc-1');
    expect(restored.profile.toJson().containsKey('deviceId'), isFalse);
    expect(restored.privateMeta.steamId64, '76561198000000000');
    expect(restored.privateMeta.deviceId, startsWith('android:'));
    expect(restored.secrets.revocationCode, 'R12345');
    expect(restored.secrets.sharedSecret, payload.secrets.sharedSecret);
    expect(restored.secrets.identitySecret, payload.secrets.identitySecret);
  });

  test('migrates legacy v1 profile identity fields into privateMeta', () {
    final legacy = jsonEncode({
      'schemaVersion': 1,
      'profile': {
        'id': 'legacy',
        'nickname': 'L',
        'loginNameHint': 'l',
        'initials': 'L',
        'avatarColorValue': 1,
        'accountName': 'old-name',
        'deviceId': 'android:legacy',
        'steamId64': '1',
        'serialNumber': 'SN',
      },
      'secrets': {
        'sharedSecretB64': 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      },
    });

    final restored = AccountPayloadCodec.decode(utf8.encode(legacy));
    expect(restored.profile.toJson().containsKey('deviceId'), isFalse);
    expect(restored.privateMeta.accountName, 'old-name');
    expect(restored.privateMeta.deviceId, 'android:legacy');
    expect(restored.privateMeta.serialNumber, 'SN');
  });

  test('rejects unsupported future schema versions', () {
    const json = '{"schemaVersion":99,"profile":{},"secrets":{}}';
    expect(
      () => AccountPayloadCodec.decode(utf8.encode(json)),
      throwsA(isA<FormatException>()),
    );
  });
}
