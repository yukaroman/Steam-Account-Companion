import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:steam_account_companion/core/network/http_steam_time_client.dart';
import 'package:steam_account_companion/features/authenticator/data/local_time_provider.dart';
import 'package:steam_account_companion/features/authenticator/data/steam_guard_authenticator_service.dart';
import 'package:steam_account_companion/features/authenticator/domain/steam_time_sync_service.dart';
import 'package:steam_account_companion/features/authenticator/domain/time_provider.dart';

/// Returns successive timestamps so RTT midpoint can be unit-tested.
class _SequenceTimeProvider implements TimeProvider {
  _SequenceTimeProvider(this._samples);
  final List<DateTime> _samples;
  var _index = 0;

  @override
  DateTime now() {
    final value = _samples[_index.clamp(0, _samples.length - 1)];
    if (_index < _samples.length - 1) _index++;
    return value;
  }
}

void main() {
  test('parses QueryTime server_time string', () async {
    final mock = MockClient((request) async {
      expect(request.url.host, 'api.steampowered.com');
      expect(request.method, 'POST');
      return http.Response(
        jsonEncode({
          'response': {'server_time': '1700000000'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = HttpSteamTimeClient(httpClient: mock);
    expect(await client.queryServerTimeSeconds(), 1700000000);
  });

  test('sync uses RTT midpoint so network delay is not full skew', () async {
    // Start local is 5s behind server; request "takes" 3s → midpoint only 3.5s behind.
    final start = DateTime.fromMillisecondsSinceEpoch(
      1700000000 * 1000 - 5000,
      isUtc: true,
    );
    final end = start.add(const Duration(milliseconds: 3000));
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'response': {'server_time': 1700000000},
        }),
        200,
      );
    });

    final sync = SteamTimeSyncService(
      timeClient: HttpSteamTimeClient(httpClient: mock),
      timeProvider: _SequenceTimeProvider([start, end]),
    );
    final result = await sync.sync();
    // midpoint = start + 1500 → offset 3500, not 5000 (start-only bug).
    expect(result.serverTimeDiffMs, 3500);
    expect(result.localTimeMs, start.millisecondsSinceEpoch + 1500);
    expect(result.serverTimeUnixSeconds, 1700000000);
  });

  test('sync rejects oversized RTT', () async {
    final start = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final end = start.add(const Duration(seconds: 8));
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'response': {'server_time': 1},
        }),
        200,
      );
    });
    final sync = SteamTimeSyncService(
      timeClient: HttpSteamTimeClient(httpClient: mock),
      timeProvider: _SequenceTimeProvider([start, end]),
      maxAcceptedRtt: const Duration(seconds: 5),
    );
    await expectLater(sync.sync(), throwsA(isA<SteamTimeSyncRttException>()));
  });

  test('authenticator uses serverTimeDiffMs when generating codes', () async {
    final service = SteamGuardAuthenticatorService.fromBase64Secrets(
      sharedSecretsBase64ByAccountId: const {
        'a': 'dGVzdC1zaGFyZWQtc2VjcmV0ISE=',
      },
      timeProvider: const LocalTimeProvider(),
      serverTimeDiffMs: 0,
    );

    // Fixed local instant where server is 20s ahead → rolls window (same as codec vector).
    final local = DateTime.fromMillisecondsSinceEpoch(100 * 1000, isUtc: true);
    final withoutSkew = service.codeFor(accountId: 'a', now: local);

    service.serverTimeDiffMs = 20000;
    final withSkew = service.codeFor(accountId: 'a', now: local);
    expect(withSkew, isNot(withoutSkew));
  });

  test('non-2xx QueryTime throws SteamTimeSyncException', () async {
    final mock = MockClient((request) async {
      return http.Response('nope', 503);
    });
    final client = HttpSteamTimeClient(httpClient: mock);
    await expectLater(
      client.queryServerTimeSeconds(),
      throwsA(isA<SteamTimeSyncException>()),
    );
  });
}
