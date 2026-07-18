import 'dart:convert';

import '../domain/authenticator_service.dart';
import '../domain/steam_guard_codec.dart';
import '../domain/time_provider.dart';
import 'local_time_provider.dart';

/// [AuthenticatorService] backed by real Steam Guard math.
///
/// Secrets are held only inside this service (or a future encrypted store).
/// Presentation code must pass [accountId] only — never raw secrets.
class SteamGuardAuthenticatorService implements AuthenticatorService {
  SteamGuardAuthenticatorService({
    required Map<String, List<int>> sharedSecretsByAccountId,
    TimeProvider? timeProvider,
    this.serverTimeDiffMs = 0,
  })  : _sharedSecretsByAccountId = Map.unmodifiable(
          sharedSecretsByAccountId.map(
            (key, value) => MapEntry(key, List<int>.unmodifiable(value)),
          ),
        ),
        _timeProvider = timeProvider ?? const LocalTimeProvider();

  /// Builds a service from Base64 `shared_secret` values (maFile field).
  factory SteamGuardAuthenticatorService.fromBase64Secrets({
    required Map<String, String> sharedSecretsBase64ByAccountId,
    TimeProvider? timeProvider,
    int serverTimeDiffMs = 0,
  }) {
    final decoded = <String, List<int>>{
      for (final entry in sharedSecretsBase64ByAccountId.entries)
        entry.key: base64.decode(_normalizeBase64(entry.value)),
    };
    return SteamGuardAuthenticatorService(
      sharedSecretsByAccountId: decoded,
      timeProvider: timeProvider,
      serverTimeDiffMs: serverTimeDiffMs,
    );
  }

  Map<String, List<int>> _sharedSecretsByAccountId;
  final TimeProvider _timeProvider;

  /// `serverNowMs - localNowMs`. Updated after QueryTime sync (later batch).
  int serverTimeDiffMs;

  /// Account ids that currently have a shared secret loaded.
  Iterable<String> get knownAccountIds => _sharedSecretsByAccountId.keys;

  bool hasSecretFor(String accountId) =>
      _sharedSecretsByAccountId.containsKey(accountId);

  /// Replaces in-memory secrets (e.g. after import). Does not touch disk.
  void replaceSharedSecrets(Map<String, List<int>> sharedSecretsByAccountId) {
    _sharedSecretsByAccountId = Map.unmodifiable(
      sharedSecretsByAccountId.map(
        (key, value) => MapEntry(key, List<int>.unmodifiable(value)),
      ),
    );
  }

  @override
  String codeFor({required String accountId, required DateTime now}) {
    final secret = _sharedSecretsByAccountId[accountId];
    if (secret == null) {
      throw StateError('No shared_secret loaded for accountId "$accountId"');
    }
    return SteamGuardCodec.codeFromSharedSecret(
      sharedSecret: secret,
      now: now,
      serverTimeDiffMs: serverTimeDiffMs,
    );
  }

  @override
  int secondsRemaining(DateTime now) {
    return SteamGuardCodec.secondsRemaining(
      now,
      serverTimeDiffMs: serverTimeDiffMs,
    );
  }

  /// Convenience when the caller does not supply [now].
  String codeForAccount(String accountId) =>
      codeFor(accountId: accountId, now: _timeProvider.now());

  static String _normalizeBase64(String value) {
    final trimmed = value.trim();
    final remainder = trimmed.length % 4;
    if (remainder == 0) return trimmed;
    return trimmed.padRight(trimmed.length + (4 - remainder), '=');
  }
}

/// Demo-only Base64 secrets for the three mock UI accounts.
///
/// These are **not** real Steam Guard keys and cannot log into Steam. They
/// exist so the token page exercises production code paths without importing
/// live maFiles.
abstract final class DemoSteamGuardSecrets {
  static const byAccountId = <String, String>{
    'mock-primary': 'dGVzdC1zaGFyZWQtc2VjcmV0ISE=',
    'mock-trading': 'MTIzNDU2Nzg5MGFiY2RlZg==',
    'mock-alt': 'SGVsbG9Xb3JsZFNlY3JldCE=',
  };

  static SteamGuardAuthenticatorService createService({
    TimeProvider? timeProvider,
    int serverTimeDiffMs = 0,
  }) {
    return SteamGuardAuthenticatorService.fromBase64Secrets(
      sharedSecretsBase64ByAccountId: byAccountId,
      timeProvider: timeProvider,
      serverTimeDiffMs: serverTimeDiffMs,
    );
  }
}
