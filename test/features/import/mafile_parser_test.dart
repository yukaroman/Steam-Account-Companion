import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/features/import/data/mafile_parser.dart';

void main() {
  const parser = MaFileParser();

  test('parses sanitized fixture maFile', () {
    final source = File('test/fixtures/mafile/sample_sanitized.maFile.json')
        .readAsStringSync();
    final data = parser.parseString(source);

    expect(data.sharedSecretBase64, isNotEmpty);
    expect(data.accountName, 'demo_import');
    expect(data.deviceId, startsWith('android:'));
    expect(data.steamId64, '76561198000000001');
    expect(data.serialNumber, 'TEST1234567890');
    expect(data.identitySecretBase64, isNotEmpty);
    expect(data.revocationCode, 'R12345');
    expect(data.sessionId, 'demo_session_id_not_real');
    expect(data.steamLoginSecure, contains('demo_token_not_real'));
  });

  test('parses AccessToken fallback into steamLoginSecure shape', () {
    final data = parser.parseString('''
{
  "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
  "identity_secret": "aWRlbnRpdHktc2VjcmV0LTE=",
  "device_id": "android:11111111-1111-4111-8111-111111111111",
  "Session": {
    "SteamID": 76561198000000099,
    "SessionID": "abc123session",
    "AccessToken": "eyJhbGciOidemo.token"
  }
}
''');
    expect(data.steamId64, '76561198000000099');
    expect(data.sessionId, 'abc123session');
    expect(data.accessToken, 'eyJhbGciOidemo.token');
    expect(
      data.steamLoginSecure,
      '76561198000000099%7C%7CeyJhbGciOidemo.token',
    );
  });

  test('parses WinAuth modern Session JSON (access_token / refresh_token)', () {
    final data = parser.parseString('''
{
  "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
  "identity_secret": "aWRlbnRpdHktc2VjcmV0LTE=",
  "device_id": "android:11111111-1111-4111-8111-111111111111",
  "Session": {
    "steamid": 76561198000000088,
    "access_token": "access-jwt",
    "refresh_token": "refresh-jwt"
  }
}
''');
    expect(data.steamId64, '76561198000000088');
    expect(data.accessToken, 'access-jwt');
    expect(data.refreshToken, 'refresh-jwt');
    expect(data.sessionId, isNull);
    expect(
      data.steamLoginSecure,
      '76561198000000088%7C%7Caccess-jwt',
    );
  });

  test('parses root cookie blob for session fields', () {
    final data = parser.parseString('''
{
  "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
  "cookies": "sessionid=root_sess; steamLoginSecure=7656119%7C%7Ctok; timezoneOffset=0"
}
''');
    expect(data.sessionId, 'root_sess');
    expect(data.steamLoginSecure, '7656119%7C%7Ctok');
  });

  test('parses SteamTools-style accounts map with uuid_key', () {
    final dataList = parser.parseAll('''
{
  "accounts": {
    "76561198000000001": {
      "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
      "identity_secret": "aWRlbnRpdHktc2VjcmV0LTE=",
      "serial_number": "1234567890",
      "revocation_code": "R00001",
      "account_name": "demo_map_user",
      "token_gid": "token-gid",
      "steamguard_scheme": 2,
      "steamid": "76561198000000001",
      "uri": "otpauth://totp/Steam:demo?secret=TEST&issuer=Steam"
    }
  },
  "uuid_key": "android:b656a73f-57ee-482c-a72b-a186edd1072b"
}
''');
    expect(dataList, hasLength(1));
    final data = dataList.single;
    expect(data.accountName, 'demo_map_user');
    expect(data.steamId64, '76561198000000001');
    expect(data.deviceId, 'android:b656a73f-57ee-482c-a72b-a186edd1072b');
    expect(data.identitySecretBase64, isNotEmpty);
    expect(data.sessionId, isNull); // no Session in this format
  });

  test('accounts map key supplies steamid when body omits it', () {
    final dataList = parser.parseAll('''
{
  "accounts": {
    "76561198000000042": {
      "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
      "account_name": "key_only_id"
    }
  },
  "uuid_key": "android:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
}
''');
    expect(dataList.single.steamId64, '76561198000000042');
    expect(dataList.single.deviceId, startsWith('android:'));
  });

  test('unwraps nested maFile / SteamGuard object', () {
    final data = parser.parseString('''
{
  "steam_username": "nested_user",
  "maFile": {
    "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
    "identity_secret": "aWRlbnRpdHktc2VjcmV0LTE=",
    "device_id": "android:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "Session": {
      "SteamID": 76561198000000111,
      "SessionID": "nested_sess",
      "SteamLoginSecure": "76561198000000111||nested_tok"
    }
  }
}
''');
    expect(data.accountName, 'nested_user');
    expect(data.deviceId, startsWith('android:'));
    expect(data.steamId64, '76561198000000111');
    expect(data.sessionId, 'nested_sess');
    expect(data.steamLoginSecure, contains('nested_tok'));
  });

  test('rejects missing shared_secret', () {
    expect(
      () => parser.parseString('{"account_name":"x"}'),
      throwsA(
        isA<MaFileParseException>().having(
          (e) => e.code,
          'code',
          'missing_shared_secret',
        ),
      ),
    );
  });

  test('rejects invalid json', () {
    expect(
      () => parser.parseString('not-json'),
      throwsA(
        isA<MaFileParseException>()
            .having((e) => e.code, 'code', 'invalid_json'),
      ),
    );
  });

  test('accepts alternate camelCase keys', () {
    final data = parser.parseString('''
{
  "sharedSecret": "AAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  "accountName": "camel",
  "deviceId": "android:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "steamId": "42"
}
''');
    expect(data.accountName, 'camel');
    expect(data.steamId64, '42');
  });

  test('parses lightweight steam_username / steam_password export', () {
    final data = parser.parseString('''
{
  "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
  "identity_secret": "aWRlbnRpdHktc2VjcmV0LTE=",
  "steam_username": "demo_user",
  "steam_password": "demo-pass-not-real",
  "extra_tool_field": 123,
  "notes": "ignored unknown keys"
}
''');
    expect(data.sharedSecretBase64, isNotEmpty);
    expect(data.identitySecretBase64, isNotEmpty);
    expect(data.accountName, 'demo_user');
    expect(data.steamPassword, 'demo-pass-not-real');
  });

  test('case-insensitive key fallback', () {
    final data = parser.parseString('''
{
  "SHARED_SECRET": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
  "Steam_Username": "CaseUser"
}
''');
    expect(data.accountName, 'CaseUser');
  });

  test('compact key matching for steam-username style', () {
    final data = parser.parseString('''
{
  "shared-secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
  "steam-username": "hyphen_user"
}
''');
    expect(data.accountName, 'hyphen_user');
  });

  test('parses single-element account array', () {
    final data = parser.parseString('''
[
  {
    "shared_secret": "dGVzdC1zaGFyZWQtc2VjcmV0ISE=",
    "steam_username": "array_user"
  }
]
''');
    expect(data.accountName, 'array_user');
  });
}
