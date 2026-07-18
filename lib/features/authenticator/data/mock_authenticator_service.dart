import '../domain/authenticator_service.dart';

/// Display-only codes with no Steam Guard math.
///
/// Prefer [SteamGuardAuthenticatorService] for production paths. Keep this
/// mock for widget tests that should not depend on crypto or secrets maps.
class MockAuthenticatorService implements AuthenticatorService {
  static const _codes = <String>[
    'N7K2R',
    '4DX9M',
    'Q8T3B',
    'W5C7P',
    'H2V6Y',
  ];

  @override
  String codeFor({required String accountId, required DateTime now}) {
    final slice = now.millisecondsSinceEpoch ~/
        const Duration(seconds: 30).inMilliseconds;
    final seed = accountId.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return _codes[(slice + seed) % _codes.length];
  }

  @override
  int secondsRemaining(DateTime now) {
    final elapsed = now.millisecondsSinceEpoch ~/ 1000;
    final remaining = 30 - (elapsed % 30);
    return remaining == 0 ? 30 : remaining;
  }
}
