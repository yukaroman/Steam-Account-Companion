import '../../accounts/data/encrypted_accounts_repository.dart';
import '../../accounts/models/steam_account_secrets.dart';
import '../domain/confirmations_repository.dart';
import '../domain/steam_mobile_session.dart';
import '../models/steam_confirmation.dart';
import 'http_steam_confirmations_client.dart';

/// Aggregates mobileconf across local accounts that have session + identity_secret.
class SteamConfirmationsRepository implements ConfirmationsRepository {
  SteamConfirmationsRepository({
    required EncryptedAccountsRepository accounts,
    required HttpSteamConfirmationsClient client,
  })  : _accounts = accounts,
        _client = client;

  final EncryptedAccountsRepository _accounts;
  final HttpSteamConfirmationsClient _client;

  @override
  Future<List<SteamConfirmation>> pending() async {
    final profiles = await _accounts.listProfiles();
    final all = <SteamConfirmation>[];
    final errors = <String>[];
    var attempted = 0;

    for (final profile in profiles) {
      final meta = await _accounts.readPrivateMeta(profile.id);
      final secrets = await _accounts.readSecrets(profile.id);
      final identity = secrets?.identitySecret;
      final steamId = meta?.steamId64;
      final deviceId = meta?.deviceId;
      if (identity == null ||
          identity.isEmpty ||
          steamId == null ||
          steamId.isEmpty ||
          deviceId == null ||
          deviceId.isEmpty ||
          secrets == null ||
          !SteamMobileSession.isUsable(
            secrets: secrets,
            steamId64: steamId,
          )) {
        continue;
      }

      attempted++;
      // Space multi-account list fetches — Steam 429 is common after login spam.
      if (attempted > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
      try {
        final session = await _prepareSession(
          accountId: profile.id,
          steamId64: steamId,
          secrets: secrets,
        );
        final items = await _client.listPending(
          accountId: profile.id,
          accountName: profile.nickname,
          steamId64: steamId,
          deviceId: deviceId,
          identitySecret: identity,
          sessionId: session.sessionId,
          steamLoginSecure: session.steamLoginSecure,
        );
        all.addAll(items);
      } on ConfirmationsException catch (error) {
        errors.add('${profile.nickname}: ${error.message}');
      } catch (_) {
        errors.add('${profile.nickname}: 网络错误');
      }
    }

    all.sort((a, b) {
      final at = a.creationTime ?? 0;
      final bt = b.creationTime ?? 0;
      return bt.compareTo(at);
    });

    if (all.isEmpty && errors.isNotEmpty) {
      throw ConfirmationsException(
        'all_failed',
        errors.join('\n'),
      );
    }
    if (attempted == 0 && profiles.isNotEmpty) {
      // No account is ready — surface a clear domain error for the UI.
      throw const ConfirmationsException(
        'not_ready',
        '当前账号还不能查询 Steam 确认。请确认：'
            '① 已导入 identity_secret 与 device_id；'
            '② 在确认页或账号详情点「登录」写入会话。'
            '也可导入含 Session 的完整 SDA/SteamTools 令牌。',
      );
    }
    return all;
  }

  @override
  Future<void> approve(SteamConfirmation confirmation) =>
      _send(confirmation, allow: true);

  @override
  Future<void> reject(SteamConfirmation confirmation) =>
      _send(confirmation, allow: false);

  Future<void> _send(SteamConfirmation confirmation,
      {required bool allow}) async {
    final meta = await _accounts.readPrivateMeta(confirmation.accountId);
    final secrets = await _accounts.readSecrets(confirmation.accountId);
    final identity = secrets?.identitySecret;
    final steamId = meta?.steamId64;
    final deviceId = meta?.deviceId;
    if (identity == null ||
        steamId == null ||
        deviceId == null ||
        secrets == null ||
        !SteamMobileSession.isUsable(
          secrets: secrets,
          steamId64: steamId,
        )) {
      throw const ConfirmationsException(
        'missing_credentials',
        '该账号缺少有效登录会话、identity_secret 或 device_id，无法提交允许/拒绝。'
            '请检查账号详情中的设备 ID，并重新登录会话。',
      );
    }

    final session = await _prepareSession(
      accountId: confirmation.accountId,
      steamId64: steamId,
      secrets: secrets,
    );

    await _client.sendDecision(
      allow: allow,
      confirmationId: confirmation.id,
      nonce: confirmation.nonce,
      steamId64: steamId,
      deviceId: deviceId,
      identitySecret: identity,
      sessionId: session.sessionId,
      steamLoginSecure: session.steamLoginSecure,
    );
  }

  /// Ensures cookies are ready; refreshes JWT when access token is expired.
  Future<SteamMobileSession> _prepareSession({
    required String accountId,
    required String steamId64,
    required SteamAccountSecrets secrets,
  }) async {
    var working = secrets;
    final tokenForExpiry = working.accessToken?.trim().isNotEmpty == true
        ? working.accessToken
        : SteamMobileSession.accessTokenFromLoginSecure(
            working.steamLoginSecure);

    if (SteamMobileSession.isAccessTokenExpired(tokenForExpiry)) {
      final refresh = working.refreshToken?.trim();
      if (refresh == null || refresh.isEmpty) {
        throw const ConfirmationsException(
          'session_expired',
          '登录令牌已过期且没有 refresh_token，请在确认页或账号详情重新登录',
        );
      }
      if (SteamMobileSession.isRefreshTokenExpired(refresh)) {
        throw const ConfirmationsException(
          'session_expired',
          'refresh_token 已过期，请在确认页或账号详情重新登录',
        );
      }

      final newAccess = await _client.refreshAccessToken(
        steamId64: steamId64,
        refreshToken: refresh,
      );
      working = working.copyWith(
        accessToken: newAccess,
        steamLoginSecure:
            SteamMobileSession.buildSteamLoginSecure(steamId64, newAccess),
        // Persist generated session id for stable CSRF cookie across calls.
        sessionId: working.sessionId?.trim().isNotEmpty == true
            ? working.sessionId
            : SteamMobileSession.generateSessionId(),
      );
      await _accounts.replaceSecrets(accountId, working);
    }

    final resolved = SteamMobileSession.resolve(
      secrets: working,
      steamId64: steamId64,
    );
    if (resolved == null) {
      throw const ConfirmationsException(
        'missing_credentials',
        '无法从令牌构造登录会话',
      );
    }

    // Persist locally generated sessionid / derived steamLoginSecure once so
    // subsequent requests reuse the same community cookies.
    final shouldPersist = (working.sessionId == null ||
            working.sessionId!.trim().isEmpty ||
            working.sessionId != resolved.sessionId) ||
        (working.steamLoginSecure == null ||
            working.steamLoginSecure!.trim().isEmpty) ||
        (working.accessToken == null && resolved.accessToken != null);

    if (shouldPersist) {
      final updated = working.copyWith(
        sessionId: resolved.sessionId,
        steamLoginSecure: resolved.steamLoginSecure,
        accessToken: resolved.accessToken ?? working.accessToken,
      );
      await _accounts.replaceSecrets(accountId, updated);
    }

    return resolved;
  }

  /// Per-account readiness for confirmations UI.
  Future<ConfirmationsReadiness> readiness() async {
    final profiles = await _accounts.listProfiles();
    final statuses = <ConfirmationAccountStatus>[];
    var readyCount = 0;
    var identityOnlyCount = 0;

    for (final profile in profiles) {
      final meta = await _accounts.readPrivateMeta(profile.id);
      final secrets = await _accounts.readSecrets(profile.id);
      final hasIdentity = secrets?.identitySecret != null &&
          secrets!.identitySecret!.isNotEmpty;
      final hasDevice = meta?.deviceId != null && meta!.deviceId!.isNotEmpty;
      final hasSteamId = meta?.steamId64 != null && meta!.steamId64!.isNotEmpty;
      final health = secrets == null
          ? SteamSessionHealth.none
          : SteamMobileSession.evaluateHealth(
              secrets: secrets,
              steamId64: meta?.steamId64,
            );
      final hasSession = health == SteamSessionHealth.active ||
          health == SteamSessionHealth.refreshable;
      final hasStoredSession = secrets != null &&
          SteamMobileSession.hasStoredSessionMaterial(secrets);
      final ready = hasIdentity && hasDevice && hasSteamId && hasSession;
      if (ready) {
        readyCount++;
      } else if (hasIdentity && hasDevice && hasSteamId && !hasSession) {
        identityOnlyCount++;
      }

      final missing = <String>[];
      if (!hasIdentity) missing.add('交易确认密钥');
      if (!hasDevice) missing.add('设备标识');
      if (!hasSteamId) missing.add('Steam 账号 ID');
      if (!hasSession) {
        missing.add(
          health == SteamSessionHealth.expired ? '有效登录会话（已过期）' : '登录会话',
        );
      }

      statuses.add(
        ConfirmationAccountStatus(
          accountId: profile.id,
          displayName: profile.nickname,
          ready: ready,
          hasIdentitySecret: hasIdentity,
          hasDeviceId: hasDevice,
          hasSteamId: hasSteamId,
          hasSession: hasSession,
          hasStoredSession: hasStoredSession,
          sessionHealth: health,
          missingLabels: missing,
        ),
      );
    }

    return ConfirmationsReadiness(
      accountCount: profiles.length,
      readyCount: readyCount,
      identityOnlyCount: identityOnlyCount,
      accounts: statuses,
    );
  }
}

class ConfirmationAccountStatus {
  const ConfirmationAccountStatus({
    required this.accountId,
    required this.displayName,
    required this.ready,
    required this.hasIdentitySecret,
    required this.hasDeviceId,
    required this.hasSteamId,
    required this.hasSession,
    this.hasStoredSession = false,
    this.sessionHealth = SteamSessionHealth.none,
    required this.missingLabels,
  });

  final String accountId;
  final String displayName;
  final bool ready;
  final bool hasIdentitySecret;
  final bool hasDeviceId;
  final bool hasSteamId;

  /// Usable for mobileconf (active or refreshable).
  final bool hasSession;

  /// Any session material on disk (including expired).
  final bool hasStoredSession;

  final SteamSessionHealth sessionHealth;
  final List<String> missingLabels;
}

class ConfirmationsReadiness {
  const ConfirmationsReadiness({
    required this.accountCount,
    required this.readyCount,
    required this.identityOnlyCount,
    this.accounts = const [],
  });

  final int accountCount;
  final int readyCount;
  final int identityOnlyCount;
  final List<ConfirmationAccountStatus> accounts;

  bool get canFetch => readyCount > 0;
}
