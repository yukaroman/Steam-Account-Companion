import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../accounts/models/steam_account_secrets.dart';

/// Resolved community cookies for mobileconf, aligned with WinAuth `SteamSession`.
///
/// Modern SteamTools / WinAuth session stores JWT `access_token` (+ optional
/// `refresh_token`). Cookies are derived at request time:
/// - `steamLoginSecure` = `{steamId}%7C%7C{accessToken}` (or stored cookie)
/// - `sessionid` is random hex when missing (WinAuth `GenerateSessionID`)
class SteamMobileSession {
  const SteamMobileSession({
    required this.sessionId,
    required this.steamLoginSecure,
    this.accessToken,
    this.refreshToken,
  });

  final String sessionId;
  final String steamLoginSecure;
  final String? accessToken;
  final String? refreshToken;

  /// True when secrets carry enough material to form community auth cookies.
  ///
  /// [steamId64] is required to mint `steamLoginSecure` from access token alone.
  static bool canResolve({
    required SteamAccountSecrets secrets,
    String? steamId64,
  }) {
    return resolve(secrets: secrets, steamId64: steamId64) != null;
  }

  /// True when any session field is stored (including expired tokens).
  static bool hasStoredSessionMaterial(SteamAccountSecrets secrets) {
    return _nonEmpty(secrets.sessionId) != null ||
        _nonEmpty(secrets.steamLoginSecure) != null ||
        _nonEmpty(secrets.accessToken) != null ||
        _nonEmpty(secrets.refreshToken) != null;
  }

  /// Presentation/domain health of a stored session (JWT exp when available).
  ///
  /// Opaque non-JWT cookies are treated as [SteamSessionHealth.active] until
  /// Steam returns `needauth` at request time.
  static SteamSessionHealth evaluateHealth({
    required SteamAccountSecrets secrets,
    String? steamId64,
    DateTime? now,
  }) {
    if (!canResolve(secrets: secrets, steamId64: steamId64)) {
      return hasStoredSessionMaterial(secrets)
          ? SteamSessionHealth.expired
          : SteamSessionHealth.none;
    }

    final access = _nonEmpty(secrets.accessToken) ??
        accessTokenFromLoginSecure(secrets.steamLoginSecure);
    final refresh = _nonEmpty(secrets.refreshToken);

    // Classic cookie / opaque token — no exp claim to inspect.
    if (access == null || jwtExpirySeconds(access) == null) {
      return SteamSessionHealth.active;
    }

    if (!isAccessTokenExpired(access, now: now)) {
      return SteamSessionHealth.active;
    }

    if (refresh != null && !isRefreshTokenExpired(refresh, now: now)) {
      return SteamSessionHealth.refreshable;
    }

    return SteamSessionHealth.expired;
  }

  /// Usable for mobileconf without a full re-login (active or auto-refreshable).
  static bool isUsable({
    required SteamAccountSecrets secrets,
    String? steamId64,
    DateTime? now,
  }) {
    final health = evaluateHealth(
      secrets: secrets,
      steamId64: steamId64,
      now: now,
    );
    return health == SteamSessionHealth.active ||
        health == SteamSessionHealth.refreshable;
  }

  /// Builds request cookies from stored secrets. Returns null when impossible.
  static SteamMobileSession? resolve({
    required SteamAccountSecrets secrets,
    String? steamId64,
    Random? random,
  }) {
    final token = _nonEmpty(secrets.accessToken) ??
        accessTokenFromLoginSecure(secrets.steamLoginSecure);
    final secure = _nonEmpty(secrets.steamLoginSecure) ??
        (token != null && _nonEmpty(steamId64) != null
            ? buildSteamLoginSecure(steamId64!, token)
            : null);
    if (secure == null) return null;

    final sessionId =
        _nonEmpty(secrets.sessionId) ?? generateSessionId(random: random);

    return SteamMobileSession(
      sessionId: sessionId,
      steamLoginSecure: secure,
      accessToken: token,
      refreshToken: _nonEmpty(secrets.refreshToken),
    );
  }

  /// WinAuth `GetSteamLoginSecure()` format: `steamId%7C%7CaccessToken`.
  ///
  /// Parsers still accept raw `||` from older imports / third-party exports.
  static String buildSteamLoginSecure(String steamId64, String accessToken) {
    return '$steamId64%7C%7C$accessToken';
  }

  /// 32 hex chars, matching WinAuth `GetRandomHexNumber(32)`.
  static String generateSessionId({Random? random}) {
    final rng = random ?? Random.secure();
    final buffer = Uint8List(16);
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = rng.nextInt(256);
    }
    return buffer.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Pulls JWT / opaque token from `{steamId}||{token}` or URL-encoded form.
  static String? accessTokenFromLoginSecure(String? steamLoginSecure) {
    final raw = _nonEmpty(steamLoginSecure);
    if (raw == null) return null;
    final decoded = Uri.decodeComponent(raw);
    final separators = ['||', '%7C%7C', '%7c%7c'];
    for (final sep in separators) {
      final idx = decoded.indexOf(sep);
      if (idx > 0 && idx + sep.length < decoded.length) {
        final token = decoded.substring(idx + sep.length).trim();
        if (token.isNotEmpty) return token;
      }
    }
    return null;
  }

  /// JWT `exp` check. Non-JWT opaque tokens are treated as not expired here
  /// (caller still relies on Steam `needauth` / HTTP 401).
  static bool isAccessTokenExpired(
    String? token, {
    DateTime? now,
    int skewSeconds = 60,
  }) {
    final exp = jwtExpirySeconds(token);
    if (exp == null) return false;
    final clock = now ?? DateTime.now().toUtc();
    final unix = clock.millisecondsSinceEpoch ~/ 1000;
    return unix + skewSeconds >= exp;
  }

  static bool isRefreshTokenExpired(
    String? token, {
    DateTime? now,
    int skewSeconds = 60,
  }) =>
      isAccessTokenExpired(token, now: now, skewSeconds: skewSeconds);

  /// Returns JWT payload `exp` (unix seconds) or null if not a 3-part JWT.
  static int? jwtExpirySeconds(String? token) {
    final raw = _nonEmpty(token);
    if (raw == null) return null;
    final parts = raw.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = _decodeJwtPart(parts[1]);
      final map = jsonDecode(payload);
      if (map is! Map) return null;
      final exp = map['exp'];
      if (exp is int) return exp;
      if (exp is num) return exp.toInt();
      if (exp is String) return int.tryParse(exp);
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _decodeJwtPart(String part) {
    var base64 = part.replaceAll('-', '+').replaceAll('_', '/');
    final rem = base64.length % 4;
    if (rem != 0) {
      base64 = base64.padRight(base64.length + (4 - rem), '=');
    }
    return utf8.decode(base64Decode(base64));
  }

  static String? _nonEmpty(String? value) {
    final t = value?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }
}

/// Local view of whether a stored Session can still drive mobileconf.
enum SteamSessionHealth {
  /// No access token / steamLoginSecure material.
  none,

  /// Tokens/cookies look usable without waiting for refresh.
  active,

  /// Access JWT expired; refresh_token still valid (client will refresh).
  refreshable,

  /// Session present but access + refresh are expired / unusable.
  expired,
}

extension SteamSessionHealthLabels on SteamSessionHealth {
  String get shortLabel => switch (this) {
        SteamSessionHealth.none => '无登录会话',
        SteamSessionHealth.active => '会话有效',
        SteamSessionHealth.refreshable => '会话可刷新',
        SteamSessionHealth.expired => '会话已过期',
      };

  String get detailLabel => switch (this) {
        SteamSessionHealth.none => '尚未登录，无法查询/处理 Steam 确认',
        SteamSessionHealth.active => '可查询并处理交易/登录确认',
        SteamSessionHealth.refreshable => '访问令牌将过期，使用前会自动刷新',
        SteamSessionHealth.expired => '请重新登录，或先清除会话再登录',
      };
}
