import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account_secrets.dart';
import 'package:steam_account_companion/features/confirmations/domain/steam_mobile_session.dart';

void main() {
  SteamAccountSecrets secrets({
    String? sessionId,
    String? steamLoginSecure,
    String? accessToken,
    String? refreshToken,
  }) {
    return SteamAccountSecrets(
      sharedSecret: Uint8List.fromList(utf8.encode('shared')),
      sessionId: sessionId,
      steamLoginSecure: steamLoginSecure,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  test('hasMobileSession true with accessToken only', () {
    final s = secrets(accessToken: 'tok');
    expect(s.hasMobileSession, isTrue);
  });

  test('hasMobileSession true with steamLoginSecure only', () {
    final s = secrets(steamLoginSecure: '765||tok');
    expect(s.hasMobileSession, isTrue);
  });

  test('hasMobileSession false without cookies or token', () {
    final s = secrets(sessionId: 'only-sess');
    expect(s.hasMobileSession, isFalse);
  });

  test('resolve builds steamLoginSecure from accessToken + steamId', () {
    final session = SteamMobileSession.resolve(
      secrets: secrets(accessToken: 'jwt.tok'),
      steamId64: '76561198000000001',
      random: Random(1),
    );
    expect(session, isNotNull);
    expect(
      session!.steamLoginSecure,
      '76561198000000001%7C%7Cjwt.tok',
    );
    expect(session.sessionId, hasLength(32));
    expect(session.accessToken, 'jwt.tok');
  });

  test('resolve reuses existing sessionId', () {
    final session = SteamMobileSession.resolve(
      secrets: secrets(
        sessionId: 'abc123sessionid0000000000000000',
        steamLoginSecure: '765||tok',
      ),
      steamId64: '765',
    );
    expect(session!.sessionId, 'abc123sessionid0000000000000000');
  });

  test('canResolve false when only accessToken without steamId', () {
    expect(
      SteamMobileSession.canResolve(
        secrets: secrets(accessToken: 'tok'),
        steamId64: null,
      ),
      isFalse,
    );
  });

  test('accessTokenFromLoginSecure handles encoded separators', () {
    expect(
      SteamMobileSession.accessTokenFromLoginSecure('765%7C%7Chello'),
      'hello',
    );
    expect(
      SteamMobileSession.accessTokenFromLoginSecure('765||hello'),
      'hello',
    );
  });

  test('jwtExpirySeconds reads exp claim', () {
    // header.payload.sig — payload {"exp": 2000000000}
    final payload =
        base64Url.encode(utf8.encode('{"exp":2000000000}')).replaceAll('=', '');
    final token = 'eyJhbGciOiJub25lIn0.$payload.sig';
    expect(SteamMobileSession.jwtExpirySeconds(token), 2000000000);
    expect(
      SteamMobileSession.isAccessTokenExpired(
        token,
        now: DateTime.utc(2020, 1, 1),
      ),
      isFalse,
    );
    expect(
      SteamMobileSession.isAccessTokenExpired(
        token,
        now: DateTime.utc(2035, 1, 1),
      ),
      isTrue,
    );
  });

  test('generateSessionId is 32 hex', () {
    final id = SteamMobileSession.generateSessionId(random: Random(42));
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('evaluateHealth none without session material', () {
    expect(
      SteamMobileSession.evaluateHealth(
        secrets: secrets(),
        steamId64: '765',
      ),
      SteamSessionHealth.none,
    );
  });

  test('evaluateHealth active for non-JWT opaque cookie', () {
    final health = SteamMobileSession.evaluateHealth(
      secrets: secrets(steamLoginSecure: '765||opaque-not-jwt'),
      steamId64: '765',
    );
    expect(health, SteamSessionHealth.active);
    expect(
        SteamMobileSession.isUsable(
          secrets: secrets(steamLoginSecure: '765||opaque-not-jwt'),
          steamId64: '765',
        ),
        isTrue);
  });

  test('evaluateHealth expired when access JWT expired and no refresh', () {
    // payload {"exp": 1}
    final payload =
        base64Url.encode(utf8.encode('{"exp":1}')).replaceAll('=', '');
    final token = 'eyJhbGciOiJub25lIn0.$payload.sig';
    final s = secrets(accessToken: token);
    expect(
      SteamMobileSession.evaluateHealth(
        secrets: s,
        steamId64: '76561198000000001',
        now: DateTime.utc(2030),
      ),
      SteamSessionHealth.expired,
    );
    expect(
      SteamMobileSession.isUsable(
        secrets: s,
        steamId64: '76561198000000001',
        now: DateTime.utc(2030),
      ),
      isFalse,
    );
  });

  test('withoutSession drops tokens and keeps guard', () {
    final full = SteamAccountSecrets(
      sharedSecret: Uint8List.fromList(utf8.encode('shared')),
      identitySecret: Uint8List.fromList(utf8.encode('id')),
      steamPassword: 'pw',
      sessionId: 'sess',
      steamLoginSecure: '765||tok',
      accessToken: 'a',
      refreshToken: 'r',
    );
    final cleared = full.withoutSession();
    expect(cleared.accessToken, isNull);
    expect(cleared.refreshToken, isNull);
    expect(cleared.sessionId, isNull);
    expect(cleared.steamLoginSecure, isNull);
    expect(cleared.steamPassword, 'pw');
    expect(cleared.sharedSecret, isNotEmpty);
    final clearedPw = full.withoutSession(clearSavedPassword: true);
    expect(clearedPw.steamPassword, isNull);
  });
}
