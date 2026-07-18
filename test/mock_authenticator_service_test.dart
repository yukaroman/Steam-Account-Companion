import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/features/authenticator/data/mock_authenticator_service.dart';

void main() {
  final service = MockAuthenticatorService();

  test('display code stays stable inside the same 30 second window', () {
    final first = DateTime.fromMillisecondsSinceEpoch(30 * 1000 * 100);
    final second = first.add(const Duration(seconds: 20));

    expect(
      service.codeFor(accountId: 'mock-primary', now: first),
      service.codeFor(accountId: 'mock-primary', now: second),
    );
  });

  test('remaining time is always between 1 and 30 seconds', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1234567890000);
    expect(service.secondsRemaining(now), inInclusiveRange(1, 30));
  });
}
