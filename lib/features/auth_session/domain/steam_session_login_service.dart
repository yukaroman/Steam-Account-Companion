import '../../accounts/data/encrypted_accounts_repository.dart';
import '../../accounts/models/steam_account_private_meta.dart';
import '../../accounts/models/steam_account_secrets.dart';
import '../../authenticator/data/steam_guard_authenticator_service.dart';
import '../../authenticator/domain/authenticator_service.dart';
import '../../authenticator/domain/steam_guard_codec.dart';
import '../../confirmations/domain/steam_mobile_session.dart';
import '../data/steam_login_client.dart';
import 'steam_login_result.dart';

/// Orchestrates password login + local Guard code and persists Session tokens.
class SteamSessionLoginService {
  SteamSessionLoginService({
    required EncryptedAccountsRepository accounts,
    required AuthenticatorService authenticator,
    required SteamLoginClient loginClient,
    DateTime Function()? now,
  })  : _accounts = accounts,
        _authenticator = authenticator,
        _loginClient = loginClient,
        _now = now ?? DateTime.now;

  final EncryptedAccountsRepository _accounts;
  final AuthenticatorService _authenticator;
  final SteamLoginClient _loginClient;
  final DateTime Function() _now;

  /// Logs in [accountId] with [username]/[password], auto-submits device Guard
  /// code from local shared_secret when Steam requests it.
  Future<SteamSessionLoginOutcome> login({
    required String accountId,
    required String username,
    required String password,
    bool rememberPassword = false,
    String? emailCode,
  }) async {
    final secrets = await _accounts.readSecrets(accountId);
    if (secrets == null || secrets.sharedSecret.isEmpty) {
      return const SteamSessionLoginError(
        '该账号没有验证码密钥，无法完成 Steam Guard 登录',
        code: 'missing_guard',
      );
    }

    // Prefer disk secrets (always present for this accountId) over in-memory
    // authenticator map, which can desync after imports and throw StateError.
    final twoFactor = _codeFromSecrets(secrets);

    final result = await _loginClient.login(
      username: username,
      password: password,
      twoFactorCode: twoFactor,
      emailCode: emailCode,
    );

    return _handleClientResult(
      accountId: accountId,
      username: username,
      password: password,
      rememberPassword: rememberPassword,
      secrets: secrets,
      result: result,
      // If first pass returned needs device code without us having sent one
      // (shouldn't happen when twoFactor is always sent), retry once.
    );
  }

  /// Completes email-code step after [SteamSessionLoginNeedEmailCode].
  Future<SteamSessionLoginOutcome> continueWithEmailCode({
    required String accountId,
    required int clientId,
    required List<int> requestId,
    required int steamId,
    required String emailCode,
    String? username,
    String? password,
    bool rememberPassword = false,
  }) async {
    final secrets = await _accounts.readSecrets(accountId);
    if (secrets == null) {
      return const SteamSessionLoginError('账号不存在', code: 'missing_account');
    }

    final result = await _loginClient.continueWithGuardCode(
      clientId: clientId,
      requestId: requestId,
      steamId: steamId,
      kind: SteamLoginGuardKind.emailCode,
      code: emailCode,
    );

    return _handleClientResult(
      accountId: accountId,
      username: username ?? '',
      password: password ?? '',
      rememberPassword: rememberPassword,
      secrets: secrets,
      result: result,
    );
  }

  Future<SteamSessionLoginOutcome> _handleClientResult({
    required String accountId,
    required String username,
    required String password,
    required bool rememberPassword,
    required SteamAccountSecrets secrets,
    required SteamLoginClientResult result,
  }) async {
    switch (result) {
      case SteamLoginSuccess(
          :final steamId64,
          :final accessToken,
          :final refreshToken
        ):
        final mismatch = await _steamIdMismatchError(
          accountId: accountId,
          steamId64: steamId64,
        );
        if (mismatch != null) return mismatch;
        await _persistSession(
          accountId: accountId,
          secrets: secrets,
          steamId64: steamId64,
          accessToken: accessToken,
          refreshToken: refreshToken,
          username: username,
          password: password,
          rememberPassword: rememberPassword,
        );
        return SteamSessionLoginOk(steamId64: steamId64);

      case SteamLoginNeedsGuard(
          kind: SteamLoginGuardKind.deviceCode,
          :final clientId,
          :final requestId,
          :final steamId,
        ):
        // One auto-retry with a fresh local Guard code (window edge / omitted).
        final code = _codeFromSecrets(secrets);
        final retry = await _loginClient.continueWithGuardCode(
          clientId: clientId,
          requestId: requestId,
          steamId: steamId,
          kind: SteamLoginGuardKind.deviceCode,
          code: code,
        );
        if (retry is SteamLoginNeedsGuard) {
          return const SteamSessionLoginError(
            '无法自动完成手机验证码登录，请稍后重试',
            code: 'guard_loop',
          );
        }
        return _handleClientResult(
          accountId: accountId,
          username: username,
          password: password,
          rememberPassword: rememberPassword,
          secrets: secrets,
          result: retry,
        );

      case SteamLoginNeedsGuard(
          kind: SteamLoginGuardKind.emailCode,
          :final clientId,
          :final requestId,
          :final steamId,
          :final emailHint,
        ):
        return SteamSessionLoginNeedEmailCode(
          clientId: clientId,
          requestId: requestId,
          steamId: steamId,
          emailHint: emailHint,
        );

      case SteamLoginFailed(:final message, :final code):
        return SteamSessionLoginError(message, code: code);
    }
  }

  String _codeFromSecrets(SteamAccountSecrets secrets) {
    var skew = 0;
    final auth = _authenticator;
    if (auth is SteamGuardAuthenticatorService) {
      skew = auth.serverTimeDiffMs;
    }
    return SteamGuardCodec.codeFromSharedSecret(
      sharedSecret: secrets.sharedSecret,
      now: _now(),
      serverTimeDiffMs: skew,
    );
  }

  /// Blocks writing another Steam account's session into this Guard record.
  Future<SteamSessionLoginError?> _steamIdMismatchError({
    required String accountId,
    required String steamId64,
  }) async {
    final meta = await _accounts.readPrivateMeta(accountId);
    final expected = meta?.steamId64?.trim();
    if (expected == null || expected.isEmpty) return null;
    if (expected == steamId64.trim()) return null;
    return SteamSessionLoginError(
      '登录返回的 SteamID 与本地账号不一致（本地 $expected，登录 ${steamId64.trim()}）。'
      '未写入任何会话，请确认用户名是否对应此令牌。',
      code: 'account_mismatch',
    );
  }

  Future<void> _persistSession({
    required String accountId,
    required SteamAccountSecrets secrets,
    required String steamId64,
    required String accessToken,
    required String refreshToken,
    required String username,
    required String password,
    required bool rememberPassword,
  }) async {
    final profile = await _accounts.getProfile(accountId);
    final meta = await _accounts.readPrivateMeta(accountId);
    if (profile == null) {
      throw StateError('account missing after login: $accountId');
    }

    final sessionId = secrets.sessionId?.trim().isNotEmpty == true
        ? secrets.sessionId!
        : SteamMobileSession.generateSessionId();
    final secure =
        SteamMobileSession.buildSteamLoginSecure(steamId64, accessToken);

    final nextSecrets = secrets.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
      steamLoginSecure: secure,
      sessionId: sessionId,
      steamPassword: rememberPassword ? password : null,
      clearSteamPassword: !rememberPassword,
    );

    final nextMeta = SteamAccountPrivateMeta(
      accountName: (meta?.accountName?.trim().isNotEmpty == true)
          ? meta!.accountName
          : (username.trim().isEmpty ? meta?.accountName : username.trim()),
      steamId64: steamId64,
      serialNumber: meta?.serialNumber,
      deviceId: meta?.deviceId,
    );

    await _accounts.upsert(
      profile: profile,
      privateMeta: nextMeta,
      secrets: nextSecrets,
    );
  }
}
