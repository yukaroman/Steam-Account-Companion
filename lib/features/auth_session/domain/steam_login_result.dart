import 'dart:typed_data';

/// Outcome of a Steam password login attempt (domain layer).
sealed class SteamLoginClientResult {
  const SteamLoginClientResult();
}

final class SteamLoginSuccess extends SteamLoginClientResult {
  const SteamLoginSuccess({
    required this.steamId64,
    required this.accessToken,
    required this.refreshToken,
  });

  final String steamId64;
  final String accessToken;
  final String refreshToken;
}

enum SteamLoginGuardKind { deviceCode, emailCode }

/// Steam requires a second step with Guard / email code.
final class SteamLoginNeedsGuard extends SteamLoginClientResult {
  const SteamLoginNeedsGuard({
    required this.kind,
    required this.clientId,
    required this.requestId,
    required this.steamId,
    this.emailHint,
  });

  final SteamLoginGuardKind kind;
  final int clientId;
  final Uint8List requestId;
  final int steamId;
  final String? emailHint;
}

final class SteamLoginFailed extends SteamLoginClientResult {
  const SteamLoginFailed(this.message, {this.code});

  final String message;
  final String? code;
}

/// Thrown inside [SteamLoginClient] for mapped protocol errors.
class SteamLoginException implements Exception {
  SteamLoginException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'SteamLoginException($code): $message';
}

/// High-level app login outcome after secrets are persisted (or not).
sealed class SteamSessionLoginOutcome {
  const SteamSessionLoginOutcome();
}

final class SteamSessionLoginOk extends SteamSessionLoginOutcome {
  const SteamSessionLoginOk({required this.steamId64});

  final String steamId64;
}

final class SteamSessionLoginNeedEmailCode extends SteamSessionLoginOutcome {
  const SteamSessionLoginNeedEmailCode({
    required this.clientId,
    required this.requestId,
    required this.steamId,
    this.emailHint,
  });

  final int clientId;
  final Uint8List requestId;
  final int steamId;
  final String? emailHint;
}

final class SteamSessionLoginError extends SteamSessionLoginOutcome {
  const SteamSessionLoginError(this.message, {this.code});

  final String message;
  final String? code;
}
