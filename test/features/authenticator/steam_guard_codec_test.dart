import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/features/authenticator/domain/steam_guard_codec.dart';

void main() {
  late List<Map<String, dynamic>> vectors;

  setUpAll(() {
    final file = File('test/fixtures/steam_guard_vectors.json');
    final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    vectors = (root['vectors'] as List).cast<Map<String, dynamic>>();
  });

  test('alphabet and period match Steam Guard / WinAuth constants', () {
    expect(SteamGuardCodec.steamChars, '23456789BCDFGHJKMNPQRTVWXY');
    expect(SteamGuardCodec.steamChars.length, 26);
    expect(SteamGuardCodec.periodSeconds, 30);
    expect(SteamGuardCodec.codeDigits, 5);
  });

  test('fixed vectors produce expected codes and remaining windows', () {
    for (final vector in vectors) {
      final id = vector['id'] as String;
      final secret = vector['shared_secret_b64'] as String;
      final unixSeconds = vector['unix_seconds'] as int;
      final serverDiff = vector['server_time_diff_ms'] as int;
      final expectedCode = vector['expected_code'] as String;
      final expectedRemaining = vector['expected_remaining'] as int;
      final now = DateTime.fromMillisecondsSinceEpoch(
        unixSeconds * 1000,
        isUtc: true,
      );

      final code = SteamGuardCodec.codeFromBase64SharedSecret(
        sharedSecretBase64: secret,
        now: now,
        serverTimeDiffMs: serverDiff,
      );
      final remaining = SteamGuardCodec.secondsRemaining(
        now,
        serverTimeDiffMs: serverDiff,
      );

      expect(code, expectedCode, reason: 'code mismatch for $id');
      expect(remaining, expectedRemaining,
          reason: 'remaining mismatch for $id');
      expect(code.length, 5, reason: 'length for $id');
      expect(
        code.split('').every(SteamGuardCodec.steamChars.contains),
        isTrue,
        reason: 'alphabet for $id',
      );
    }
  });

  test('code is stable inside the same 30 second window', () {
    const secret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    final start =
        DateTime.fromMillisecondsSinceEpoch(30 * 1000 * 40, isUtc: true);
    final mid = start.add(const Duration(seconds: 20));

    expect(
      SteamGuardCodec.codeFromBase64SharedSecret(
        sharedSecretBase64: secret,
        now: start,
      ),
      SteamGuardCodec.codeFromBase64SharedSecret(
        sharedSecretBase64: secret,
        now: mid,
      ),
    );
  });

  test('code changes when the 30 second window rolls', () {
    const secret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    final before = DateTime.fromMillisecondsSinceEpoch(29 * 1000, isUtc: true);
    final after = DateTime.fromMillisecondsSinceEpoch(30 * 1000, isUtc: true);

    expect(
      SteamGuardCodec.codeFromBase64SharedSecret(
        sharedSecretBase64: secret,
        now: before,
      ),
      isNot(
        SteamGuardCodec.codeFromBase64SharedSecret(
          sharedSecretBase64: secret,
          now: after,
        ),
      ),
    );
  });

  test('empty shared secret is rejected', () {
    expect(
      () => SteamGuardCodec.codeFromSharedSecret(
        sharedSecret: const [],
        now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      throwsArgumentError,
    );
  });
}
