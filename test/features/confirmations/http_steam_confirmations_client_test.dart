import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:steam_account_companion/features/confirmations/data/http_steam_confirmations_client.dart';
import 'package:steam_account_companion/features/confirmations/models/steam_confirmation.dart';

void main() {
  final identity = base64.decode('aWRlbnRpdHktc2VjcmV0LTE=');

  test('listPending uses list tag and parses conf array', () async {
    late http.Request seen;
    final client = HttpSteamConfirmationsClient(
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'success': 1,
            'conf': [
              {
                'id': '99',
                'nonce': 'nonce-1',
                'type': 2,
                'headline': 'Trade Offer',
                'type_name': 'Trade',
                'creation_time': 1700000000,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      timeout: const Duration(seconds: 2),
    );

    final items = await client.listPending(
      accountId: 'steam:1',
      accountName: 'demo',
      steamId64: '76561198000000001',
      deviceId: 'android:uuid',
      identitySecret: identity,
      sessionId: 'sess',
      steamLoginSecure: '765||tok',
    );

    expect(seen.method, 'GET');
    expect(seen.url.path, '/mobileconf/getlist');
    expect(seen.url.queryParameters['tag'], 'list');
    expect(seen.url.queryParameters['m'], 'react');
    expect(seen.headers['cookie'], contains('sessionid=sess'));
    expect(seen.headers['cookie'], contains('steamLoginSecure=765||tok'));
    expect(seen.headers['cookie'], contains('mobileClient=android'));
    expect(items, hasLength(1));
    expect(items.single.kind, ConfirmationKind.trade);
  });

  test('listPending does not substitute creator id for a missing nonce',
      () async {
    final client = HttpSteamConfirmationsClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': 1,
            'conf': [
              {
                'id': '99',
                'creator_id': 'trade-creator',
                'creator': 'legacy-creator',
                'type': 2,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      timeout: const Duration(seconds: 2),
    );

    final items = await client.listPending(
      accountId: 'steam:1',
      accountName: 'demo',
      steamId64: '76561198000000001',
      deviceId: 'android:uuid',
      identitySecret: identity,
      sessionId: 'sess',
      steamLoginSecure: '765||tok',
    );

    expect(items, isEmpty);
  });

  test('refreshAccessToken posts GenerateAccessTokenForApp', () async {
    late http.Request seen;
    final client = HttpSteamConfirmationsClient(
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'response': {'access_token': 'new-access-token'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      timeout: const Duration(seconds: 2),
    );

    final token = await client.refreshAccessToken(
      steamId64: '76561198000000001',
      refreshToken: 'refresh-jwt',
    );

    expect(token, 'new-access-token');
    expect(seen.method, 'POST');
    expect(
      seen.url.path,
      '/IAuthenticationService/GenerateAccessTokenForApp/v1/',
    );
    expect(seen.body, contains('refresh_token=refresh-jwt'));
    expect(seen.body, contains('steamid=76561198000000001'));
  });

  test('sendDecision posts multiajaxop with accept tag and requires success',
      () async {
    late http.Request seen;
    final client = HttpSteamConfirmationsClient(
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({'success': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      timeout: const Duration(seconds: 2),
    );

    await client.sendDecision(
      allow: true,
      confirmationId: '99',
      nonce: 'nonce-1',
      steamId64: '76561198000000001',
      deviceId: 'android:uuid',
      identitySecret: identity,
      sessionId: 'sess',
      steamLoginSecure: '765||tok',
    );

    expect(seen.method, 'POST');
    expect(seen.url.path, '/mobileconf/multiajaxop');
    expect(seen.headers['origin']?.toLowerCase(), 'https://steamcommunity.com');
    final body = seen.body;
    expect(body, contains('op=allow'));
    expect(body, contains('tag=accept'));
    expect(
      body.contains('cid%5B%5D=99') || body.contains('cid[]=99'),
      isTrue,
      reason: 'body should include cid[] for confirmation id, got $body',
    );
  });

  test('sendDecision rejects HTML login page as failure', () async {
    final client = HttpSteamConfirmationsClient(
      httpClient: MockClient((request) async {
        return http.Response(
          '<html>Steam sign in</html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      }),
      timeout: const Duration(seconds: 2),
    );

    expect(
      () => client.sendDecision(
        allow: true,
        confirmationId: '99',
        nonce: 'nonce-1',
        steamId64: '76561198000000001',
        deviceId: 'android:uuid',
        identitySecret: identity,
        sessionId: 'sess',
        steamLoginSecure: '765||tok',
      ),
      throwsA(
        isA<ConfirmationsException>().having(
          (e) => e.code,
          'code',
          'session_expired',
        ),
      ),
    );
  });

  test('listPending surfaces success=false as list_rejected not session',
      () async {
    final client = HttpSteamConfirmationsClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'message': 'bad device or key',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      timeout: const Duration(seconds: 2),
    );

    expect(
      () => client.listPending(
        accountId: 'steam:1',
        accountName: 'demo',
        steamId64: '76561198000000001',
        deviceId: 'android:uuid',
        identitySecret: identity,
        sessionId: 'sess',
        steamLoginSecure: '765||tok',
      ),
      throwsA(
        isA<ConfirmationsException>()
            .having((e) => e.code, 'code', 'list_rejected')
            .having((e) => e.message, 'message', contains('bad device')),
      ),
    );
  });

  test('listPending rejects string false instead of treating it as empty',
      () async {
    final client = HttpSteamConfirmationsClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': 'false',
            'message': 'request rejected',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      timeout: const Duration(seconds: 2),
    );

    expect(
      () => client.listPending(
        accountId: 'steam:1',
        accountName: 'demo',
        steamId64: '76561198000000001',
        deviceId: 'android:uuid',
        identitySecret: identity,
        sessionId: 'sess',
        steamLoginSecure: '765||tok',
      ),
      throwsA(
        isA<ConfirmationsException>()
            .having((e) => e.code, 'code', 'list_rejected')
            .having((e) => e.message, 'message', contains('request rejected')),
      ),
    );
  });

  test('listPending accepts omitted success only when conf is a list',
      () async {
    var includeConf = true;
    final client = HttpSteamConfirmationsClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode(
              includeConf ? {'conf': <Object>[]} : {'message': 'missing'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      timeout: const Duration(seconds: 2),
    );

    Future<List<SteamConfirmation>> list() => client.listPending(
          accountId: 'steam:1',
          accountName: 'demo',
          steamId64: '76561198000000001',
          deviceId: 'android:uuid',
          identitySecret: identity,
          sessionId: 'sess',
          steamLoginSecure: '765||tok',
        );

    await expectLater(list(), completion(isEmpty));
    includeConf = false;
    await expectLater(
      list(),
      throwsA(
        isA<ConfirmationsException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('sendDecision rejects JSON without success', () async {
    final client = HttpSteamConfirmationsClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'nope'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      timeout: const Duration(seconds: 2),
    );

    expect(
      () => client.sendDecision(
        allow: false,
        confirmationId: '99',
        nonce: 'nonce-1',
        steamId64: '76561198000000001',
        deviceId: 'android:uuid',
        identitySecret: identity,
        sessionId: 'sess',
        steamLoginSecure: '765||tok',
      ),
      throwsA(isA<ConfirmationsException>()),
    );
  });
}
