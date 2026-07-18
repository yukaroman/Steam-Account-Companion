/// Produces Steam Guard style codes for display and copy.
///
/// Implementations must not expose raw `shared_secret` values to callers.
/// Presentation layers pass only [accountId] and a clock sample.
abstract interface class AuthenticatorService {
  /// Five-character code for [accountId] at [now] (after optional server skew).
  String codeFor({required String accountId, required DateTime now});

  /// Seconds left in the current 30s window (range 1–30).
  int secondsRemaining(DateTime now);
}
