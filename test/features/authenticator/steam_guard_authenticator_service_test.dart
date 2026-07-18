import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/features/authenticator/data/steam_guard_authenticator_service.dart';
import 'package:steam_account_companion/features/authenticator/domain/time_provider.dart';

class _FixedTimeProvider implements TimeProvider {
  _FixedTimeProvider(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  // ignore: use_setters_to_change_properties
  void setNow(DateTime value) => _now = value;
}

void main() {
  test('resolves demo account codes from Base64 secrets', () {
    final service = SteamGuardAuthenticatorService.fromBase64Secrets(
      sharedSecretsBase64ByAccountId: const {
        'mock-primary': 'dGVzdC1zaGFyZWQtc2VjcmV0ISE=',
      },
    );

    final now = DateTime.fromMillisecondsSinceEpoch(
      1700000000 * 1000,
      isUtc: true,
    );

    expect(
      service.codeFor(accountId: 'mock-primary', now: now),
      '6CMP4',
    );
    expect(service.secondsRemaining(now), 10);
  });

  test('DemoSteamGuardSecrets covers all mock UI accounts', () {
    final service = DemoSteamGuardSecrets.createService();
    expect(service.hasSecretFor('mock-primary'), isTrue);
    expect(service.hasSecretFor('mock-trading'), isTrue);
    expect(service.hasSecretFor('mock-alt'), isTrue);

    final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final id in DemoSteamGuardSecrets.byAccountId.keys) {
      final code = service.codeFor(accountId: id, now: now);
      expect(code.length, 5);
    }
  });

  test('unknown accountId throws without leaking other secrets', () {
    final service = SteamGuardAuthenticatorService.fromBase64Secrets(
      sharedSecretsBase64ByAccountId: const {
        'known': 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      },
    );

    expect(
      () => service.codeFor(
        accountId: 'missing',
        now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('serverTimeDiffMs rolls the code window', () {
    final service = SteamGuardAuthenticatorService.fromBase64Secrets(
      sharedSecretsBase64ByAccountId: const {
        'a': 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      },
      serverTimeDiffMs: 20000,
    );

    final now = DateTime.fromMillisecondsSinceEpoch(100 * 1000, isUtc: true);
    expect(service.codeFor(accountId: 'a', now: now), '6NCWD');
    expect(service.secondsRemaining(now), 30);
  });

  test('codeForAccount uses injected TimeProvider', () {
    final clock = _FixedTimeProvider(
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );
    final service = DemoSteamGuardSecrets.createService(timeProvider: clock);

    expect(service.codeForAccount('mock-primary'), '6CMP4');

    clock.setNow(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(service.codeForAccount('mock-primary'), isNot('6CMP4'));
  });
}
