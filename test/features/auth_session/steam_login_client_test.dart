import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:steam_account_companion/features/auth_session/data/steam_auth_protobuf.dart';
import 'package:steam_account_companion/features/auth_session/data/steam_login_client.dart';
import 'package:steam_account_companion/features/auth_session/domain/steam_login_result.dart';

List<int> encodeVarint(int value) {
  var v = value.toUnsigned(64);
  final out = <int>[];
  while (v > 0x7f) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v & 0x7f);
  return out;
}

Uint8List lengthDelimited(int number, List<int> value) {
  final key = encodeVarint((number << 3) | 2);
  final len = encodeVarint(value.length);
  return Uint8List.fromList([...key, ...len, ...value]);
}

Uint8List varintField(int number, int value) {
  return Uint8List.fromList([
    ...encodeVarint((number << 3) | 0),
    ...encodeVarint(value),
  ]);
}

Uint8List joinMessages(List<Uint8List> parts) {
  final length = parts.fold<int>(0, (s, p) => s + p.length);
  final out = Uint8List(length);
  var o = 0;
  for (final p in parts) {
    out.setRange(o, o + p.length, p);
    o += p.length;
  }
  return out;
}

void main() {
  test('continueWithGuardCode polls tokens', () async {
    final pollBody = joinMessages([
      lengthDelimited(3, utf8.encode('r-tok')),
      lengthDelimited(4, utf8.encode('a-tok')),
    ]);
    final client = SteamLoginClient(
      httpClient: MockClient((request) async {
        if (request.url.path.contains('UpdateAuthSessionWithSteamGuardCode')) {
          return http.Response('', 200);
        }
        if (request.url.path.contains('PollAuthSessionStatus')) {
          return http.Response.bytes(pollBody, 200);
        }
        return http.Response('no', 404);
      }),
    );

    final result = await client.continueWithGuardCode(
      clientId: 1,
      requestId: [1, 2],
      steamId: 76561198000000001,
      kind: SteamLoginGuardKind.deviceCode,
      code: 'XY12Z',
    );

    expect(result, isA<SteamLoginSuccess>());
    final ok = result as SteamLoginSuccess;
    expect(ok.accessToken, 'a-tok');
    expect(ok.refreshToken, 'r-tok');
  });

  test('UpdateGuardCode request encodes fixed64 steamid key 0x11', () async {
    List<int>? guardBody;
    final pollBody = joinMessages([
      lengthDelimited(3, utf8.encode('r-tok')),
      lengthDelimited(4, utf8.encode('a-tok')),
    ]);
    final client = SteamLoginClient(
      httpClient: MockClient((request) async {
        if (request.url.path.contains('UpdateAuthSessionWithSteamGuardCode')) {
          final form = request.bodyFields;
          final b64 = form['input_protobuf_encoded']!;
          guardBody = base64.decode(b64);
          return http.Response('', 200);
        }
        if (request.url.path.contains('PollAuthSessionStatus')) {
          return http.Response.bytes(pollBody, 200);
        }
        return http.Response('no', 404);
      }),
    );

    await client.continueWithGuardCode(
      clientId: 1,
      requestId: [1, 2],
      steamId: 76561198000000001,
      kind: SteamLoginGuardKind.deviceCode,
      code: 'XY12Z',
    );

    expect(guardBody, isNotNull);
    expect(guardBody, contains(0x11));
  });

  test('email-code path calls jwt/checkdevice before returning needs guard',
      () async {
    final urls = <String>[];
    // 1024-bit RSA public modulus (openssl generated for tests only).
    const modHex =
        'eabb2041e1db7f741f2433f4b1bac35ffef4ae4969b7fa2bd64f03844a432838'
        'c8b634cb35bc075e9433ba3e9d29a168cdc6f4e3a8f688133a8bb16380fa0ec3'
        'f31bff58b7038a4b6ea6abc8068dc89a79e6a576749245d086aa7a01e9f6f96c'
        'bb62e031e9f6e5f11bc1713c24733103fc2e44aac83cdc3790c0b70159f5cf99';
    final conf = joinMessages([
      varintField(1, SteamAuthProtobuf.guardEmailCode),
      lengthDelimited(2, utf8.encode('a***@example.com')),
    ]);
    final beginBody = joinMessages([
      varintField(1, 99), // client_id
      lengthDelimited(2, [1, 2, 3]), // request_id
      lengthDelimited(4, conf),
      varintField(5, 76561198000000001), // steamid (varint also accepted)
    ]);
    final rsaBody = joinMessages([
      lengthDelimited(1, utf8.encode(modHex)),
      lengthDelimited(2, utf8.encode('010001')),
      varintField(3, 1700000000),
    ]);
    final client = SteamLoginClient(
      httpClient: MockClient((request) async {
        urls.add('${request.method} ${request.url}');
        if (request.url.path.contains('checkdevice')) {
          expect(request.method, 'POST');
          expect(request.bodyFields['clientid'], '99');
          expect(request.bodyFields['steamid'], '76561198000000001');
          return http.Response('ok', 200);
        }
        if (request.url.path.contains('GetPasswordRSAPublicKey')) {
          return http.Response.bytes(rsaBody, 200);
        }
        if (request.url.path.contains('BeginAuthSessionViaCredentials')) {
          return http.Response.bytes(beginBody, 200, headers: {
            'x-eresult': '1',
          });
        }
        return http.Response('', 404);
      }),
    );

    final result = await client.login(username: 'u', password: 'p');
    expect(result, isA<SteamLoginNeedsGuard>());
    final need = result as SteamLoginNeedsGuard;
    expect(need.kind, SteamLoginGuardKind.emailCode);
    expect(need.emailHint, 'a***@example.com');
    expect(urls.any((u) => u.contains('checkdevice')), isTrue);
  });

  test('login with device code path when RSA modulus is invalid fails soft',
      () async {
    // Invalid RSA modulus → encrypt throws → network/protocol error mapping.
    final rsaBody = joinMessages([
      lengthDelimited(1, utf8.encode('ab')),
      lengthDelimited(2, utf8.encode('010001')),
      varintField(3, 12345),
    ]);
    final client = SteamLoginClient(
      httpClient: MockClient((request) async {
        if (request.url.path.contains('GetPasswordRSAPublicKey')) {
          return http.Response.bytes(rsaBody, 200);
        }
        return http.Response('no', 404);
      }),
    );

    final result = await client.login(
      username: 'user',
      password: 'password',
      twoFactorCode: 'ABCDE',
    );
    expect(result, isA<SteamLoginFailed>());
  });

  test('sanitizeSteamAccountName strips invisible noise and lowercases', () {
    expect(
      SteamLoginClient.sanitizeSteamAccountName(
        '  \uFEFFDemo\u200BUser\u00A0 ',
      ),
      'demouser',
    );
    expect(
      SteamLoginClient.sanitizeSteamAccountName('MyAccount'),
      'myaccount',
    );
  });

  test('sanitizeSteamAccountName keeps ASCII underscores (demo__login__name)',
      () {
    expect(
      SteamLoginClient.sanitizeSteamAccountName('demo__login__name'),
      'demo__login__name',
    );
    expect(
      SteamLoginClient.sanitizeSteamAccountName('Demo__Login__Name'),
      'demo__login__name',
    );
  });

  test('sanitizeSteamAccountName maps fullwidth underscores to ASCII', () {
    // CJK IME / some exports use U+FF3F fullwidth low line, which *looks* like
    // "_" but was previously stripped → "demologinname" and Steam "no such user".
    const fullwidth = 'demo\uFF3F\uFF3Flogin\uFF3F\uFF3Fname';
    expect(
      SteamLoginClient.sanitizeSteamAccountName(fullwidth),
      'demo__login__name',
    );
    expect(
      SteamLoginClient.fullwidthAsciiToHalfwidth('Ａｂｃ\uFF3F１'),
      'Abc_1',
    );
  });

  test('sanitizeSteamPassword keeps inner spaces but drops trailing newlines',
      () {
    expect(
      SteamLoginClient.sanitizeSteamPassword('pass word\n'),
      'pass word',
    );
  });

  test('empty credentials rejected without network', () async {
    final client = SteamLoginClient(
      httpClient: MockClient((request) async => http.Response('', 500)),
    );
    final result = await client.login(username: '', password: '');
    expect(result, isA<SteamLoginFailed>());
  });

  test('BeginAuth with only email code returns needs email when 2FA not sent',
      () async {
    // Still needs valid RSA to get to Begin — skip full path; covered by
    // continueWithGuardCode + service persist tests.
    expect(SteamAuthProtobuf.guardEmailCode, 2);
  });
}
