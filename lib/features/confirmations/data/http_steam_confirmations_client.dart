import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../authenticator/domain/time_provider.dart';
import '../domain/steam_confirmation_codec.dart';
import '../models/steam_confirmation.dart';

/// Low-level Steam Community mobileconf client (personal-use).
///
/// Protocol aligned with SteamTools' pinned WinAuth SteamClient:
/// - list HMAC/query tag: `list`
/// - decision HMAC tags: `accept` / `reject`
/// - decision op: `allow` / `cancel`
/// - decision endpoint: `POST /mobileconf/multiajaxop` with `cid[]` / `ck[]`
/// - platform marker: `m=react` (current WinAuth)
///
/// Session cookies follow WinAuth `SteamSession.GetCookies`:
/// - `steamLoginSecure` = `{steamId}%7C%7C{accessToken}` (or stored cookie)
/// - `sessionid` may be generated locally when missing
///
/// Requires identity_secret + modern JWT or classic session cookies.
/// Protocol is unofficial and may change.
class HttpSteamConfirmationsClient {
  HttpSteamConfirmationsClient({
    http.Client? httpClient,
    TimeProvider? timeProvider,
    this.serverTimeDiffMs = 0,
    this.userAgent = _defaultUserAgent,
    this.timeout = const Duration(seconds: 20),
    this.maxAttempts = 3,
  })  : _http = httpClient ?? http.Client(),
        _timeProvider = timeProvider;

  /// Matches WinAuth default mobile community user-agent closely enough.
  static const _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 8.1.0; Nexus 5X Build/OPM7.181205.001) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Mobile Safari/537.36';

  static const _base = 'https://steamcommunity.com/mobileconf';
  static const _tokenRefreshUrl =
      'https://api.steampowered.com/IAuthenticationService/GenerateAccessTokenForApp/v1/';

  final http.Client _http;
  final TimeProvider? _timeProvider;
  int serverTimeDiffMs;
  final String userAgent;
  final Duration timeout;
  final int maxAttempts;

  /// Serialize community requests so multi-account refresh cannot stampede Steam.
  Future<void> _requestGate = Future<void>.value();

  /// Lists pending confirmations for one Steam account.
  Future<List<SteamConfirmation>> listPending({
    required String accountId,
    required String accountName,
    required String steamId64,
    required String deviceId,
    required List<int> identitySecret,
    required String sessionId,
    required String steamLoginSecure,
  }) async {
    final time = _steamTimeSeconds();
    final key = SteamConfirmationCodec.confirmationKey(
      identitySecret: identitySecret,
      timeSeconds: time,
      tag: 'list',
    );

    final uri = Uri.parse('$_base/getlist').replace(
      queryParameters: {
        'p': deviceId,
        'a': steamId64,
        'k': key,
        't': '$time',
        'm': 'react',
        'tag': 'list',
      },
    );

    final response = await _send(
      () => _http.get(
        uri,
        headers: _headers(
          sessionId: sessionId,
          steamLoginSecure: steamLoginSecure,
        ),
      ),
      action: '拉取确认列表',
    );

    final map = _requireJsonObject(response, action: '拉取确认列表');
    _ensureAuthSuccess(map);

    final confRaw = map['conf'];
    if (confRaw is! List) return const [];

    final items = <SteamConfirmation>[];
    for (final entry in confRaw) {
      if (entry is! Map) continue;
      final conf = Map<String, Object?>.from(entry);
      final id = '${conf['id'] ?? ''}'.trim();
      // `nonce` is the creator key submitted as ck[]. `creator_id` identifies
      // the trade/market operation and is not interchangeable with it.
      final nonce = '${conf['nonce'] ?? ''}'.trim();
      if (id.isEmpty || nonce.isEmpty) continue;

      final type = _asInt(conf['type']) ?? 0;
      final headline = '${conf['headline'] ?? conf['type_name'] ?? '确认请求'}';
      final summary = conf['summary'];
      final subtitle = summary is List
          ? summary.map((e) => '$e').where((s) => s.isNotEmpty).join(' · ')
          : '${conf['type_name'] ?? ''}';

      final creation = _asInt(conf['creation_time']);
      items.add(
        SteamConfirmation(
          id: id,
          nonce: nonce,
          accountId: accountId,
          accountName: accountName,
          kind: _mapKind(type, headline, subtitle),
          title: headline.isEmpty ? 'Steam 确认' : headline,
          subtitle: subtitle.isEmpty ? '类型 $type' : subtitle,
          timeLabel: _formatTime(creation),
          risk: _mapRisk(type),
          creationTime: creation,
          iconUrl: conf['icon'] as String?,
        ),
      );
    }
    return items;
  }

  /// Approves or cancels one confirmation.
  Future<void> sendDecision({
    required bool allow,
    required String confirmationId,
    required String nonce,
    required String steamId64,
    required String deviceId,
    required List<int> identitySecret,
    required String sessionId,
    required String steamLoginSecure,
  }) async {
    // WinAuth: HMAC tag accept/reject; form op allow/cancel.
    final tag = allow ? 'accept' : 'reject';
    final op = allow ? 'allow' : 'cancel';
    final time = _steamTimeSeconds();
    final key = SteamConfirmationCodec.confirmationKey(
      identitySecret: identitySecret,
      timeSeconds: time,
      tag: tag,
    );

    final uri = Uri.parse('$_base/multiajaxop');
    final body = <String, String>{
      'op': op,
      'p': deviceId,
      'a': steamId64,
      'k': key,
      't': '$time',
      'm': 'react',
      'tag': tag,
      // WinAuth posts repeated cid[] / ck[] form fields.
      'cid[]': confirmationId,
      'ck[]': nonce,
    };

    final response = await _send(
      () => _http.post(
        uri,
        headers: {
          ..._headers(
            sessionId: sessionId,
            steamLoginSecure: steamLoginSecure,
          ),
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          'Origin': 'https://steamcommunity.com',
          'Referer': 'https://steamcommunity.com/mobileconf/conf',
        },
        body: body,
      ),
      action: '提交确认操作',
    );

    final map = _requireJsonObject(response, action: '提交确认操作');
    if (!_isExplicitSuccess(map['success'])) {
      final message = '${map['message'] ?? map['error'] ?? '操作未成功'}';
      throw ConfirmationsException('rejected', message);
    }
  }

  /// Refreshes JWT access token via Steam
  /// `IAuthenticationService/GenerateAccessTokenForApp` (WinAuth).
  Future<String> refreshAccessToken({
    required String steamId64,
    required String refreshToken,
  }) async {
    final response = await _send(
      () => _http.post(
        Uri.parse(_tokenRefreshUrl),
        headers: {
          'User-Agent': userAgent,
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          'Accept': 'application/json, text/plain, */*',
        },
        body: {
          'refresh_token': refreshToken,
          'steamid': steamId64,
        },
      ),
      action: '刷新登录令牌',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ConfirmationsException(
        'token_refresh_failed',
        '刷新登录令牌失败（HTTP ${response.statusCode}）',
      );
    }

    final Object decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const ConfirmationsException(
        'token_refresh_failed',
        '刷新登录令牌失败：响应无效',
      );
    }
    if (decoded is! Map) {
      throw const ConfirmationsException(
        'token_refresh_failed',
        '刷新登录令牌失败：响应格式无效',
      );
    }
    final map = Map<String, Object?>.from(decoded);
    final responseNode = map['response'];
    if (responseNode is! Map) {
      throw const ConfirmationsException(
        'token_refresh_failed',
        '刷新登录令牌失败：缺少 response',
      );
    }
    final access = '${responseNode['access_token'] ?? ''}'.trim();
    if (access.isEmpty) {
      throw const ConfirmationsException(
        'token_refresh_failed',
        '刷新登录令牌失败：未返回 access_token',
      );
    }
    return access;
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    required String action,
  }) async {
    // Chain requests so getlist / multiajaxop / token refresh are spaced.
    final previous = _requestGate;
    final done = Completer<void>();
    _requestGate = previous.catchError((_) {}).then((_) => done.future);
    await previous.catchError((_) {});
    try {
      Object? lastError;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final response = await request().timeout(timeout);
          if (response.statusCode == 429) {
            final retryAfter = _retryAfterSeconds(response);
            if (attempt < maxAttempts) {
              await Future<void>.delayed(
                Duration(seconds: retryAfter ?? (2 * attempt + 1)),
              );
              continue;
            }
            throw ConfirmationsException(
              'rate_limited',
              '$action失败：请求过于频繁（HTTP 429）。'
                  '请等待约 ${retryAfter ?? 30} 秒后再点刷新，勿连续重试',
            );
          }
          return response;
        } on TimeoutException {
          lastError = ConfirmationsException(
            'timeout',
            '$action超时，请检查网络后重试',
          );
        } on ConfirmationsException {
          rethrow;
        } catch (error) {
          lastError = ConfirmationsException(
            'network',
            '$action失败：网络错误',
          );
        }
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
      final err = lastError;
      if (err is ConfirmationsException) throw err;
      throw ConfirmationsException('network', '$action失败：网络错误');
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }

  static int? _retryAfterSeconds(http.Response response) {
    final raw =
        response.headers['retry-after'] ?? response.headers['Retry-After'];
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  Map<String, Object?> _requireJsonObject(
    http.Response response, {
    required String action,
  }) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ConfirmationsException(
        'session_expired',
        '登录会话已失效，请在确认页或账号详情重新登录',
      );
    }
    if (response.statusCode == 429) {
      final retryAfter = _retryAfterSeconds(response);
      throw ConfirmationsException(
        'rate_limited',
        '$action失败：Steam 限流（HTTP 429）。'
            '请等待约 ${retryAfter ?? 30} 秒后再刷新',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ConfirmationsException(
        'http_${response.statusCode}',
        '$action失败（HTTP ${response.statusCode}）',
      );
    }

    final body = response.body.trim();
    if (body.isEmpty) {
      throw ConfirmationsException(
        'invalid_response',
        '$action失败：空响应',
      );
    }
    // Login redirect / HTML must never count as success.
    if (body.startsWith('<') ||
        body.toLowerCase().contains('<html') ||
        body.toLowerCase().contains('g_sessionid')) {
      throw const ConfirmationsException(
        'session_expired',
        '登录会话已失效或被重定向到登录页，请重新登录会话',
      );
    }

    final Object decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ConfirmationsException(
        'invalid_response',
        '$action失败：响应不是 JSON',
      );
    }
    if (decoded is! Map) {
      throw ConfirmationsException(
        'invalid_response',
        '$action失败：响应格式无效',
      );
    }
    return Map<String, Object?>.from(decoded);
  }

  void _ensureAuthSuccess(Map<String, Object?> map) {
    final needAuth = _isExplicitSuccess(map['needauth']);
    final steamMessage = _steamMessage(map);

    if (needAuth) {
      throw ConfirmationsException(
        'session_expired',
        steamMessage ?? '登录会话无效（needauth），请重新登录后再刷新确认',
      );
    }

    final success = map['success'];
    if (_isExplicitSuccess(success)) return;

    // Some list responses omit success when conf is present; WinAuth still accepts.
    if (success == null && map['conf'] is List) return;

    if (_isExplicitFailure(success)) {
      // Wrong identity_secret / device_id / clock often lands here — not always session.
      throw ConfirmationsException(
        'list_rejected',
        steamMessage ??
            'Steam 拒绝确认列表（success=false）。请核对 device_id、'
                'identity_secret，并确认本机已校时后重试',
      );
    }

    throw ConfirmationsException(
      'invalid_response',
      steamMessage ?? (success == null ? '确认列表响应缺少成功标记' : '确认列表响应包含无效的成功标记'),
    );
  }

  static String? _steamMessage(Map<String, Object?> map) {
    for (final key in ['message', 'error', 'detail', 'errmsg']) {
      final raw = map[key];
      if (raw == null) continue;
      final text = '$raw'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return null;
  }

  static bool _isExplicitSuccess(Object? success) {
    return success == true ||
        success == 1 ||
        success == '1' ||
        success == 'true';
  }

  static bool _isExplicitFailure(Object? success) {
    return success == false ||
        success == 0 ||
        success == '0' ||
        success == 'false';
  }

  Map<String, String> _headers({
    required String sessionId,
    required String steamLoginSecure,
  }) {
    // Align cookie set with WinAuth GetCookies (community domain).
    return {
      'User-Agent': userAgent,
      'Accept': 'application/json, text/plain, */*',
      'Cookie': 'sessionid=$sessionId; steamLoginSecure=$steamLoginSecure; '
          'mobileClient=android; mobileClientVersion=777777 3.6.1',
      'X-Requested-With': 'com.valvesoftware.android.steam.community',
    };
  }

  int _steamTimeSeconds() {
    final now = _timeProvider?.now() ?? DateTime.now();
    final adjustedMs = now.millisecondsSinceEpoch + serverTimeDiffMs;
    return adjustedMs ~/ 1000;
  }

  static ConfirmationKind _mapKind(int type, String headline, String subtitle) {
    final blob = '${headline.toLowerCase()} ${subtitle.toLowerCase()}';
    if (type == 2 || blob.contains('trade') || blob.contains('交易')) {
      return ConfirmationKind.trade;
    }
    if (type == 3 ||
        type == 5 ||
        blob.contains('market') ||
        blob.contains('市场') ||
        blob.contains('listing')) {
      return ConfirmationKind.market;
    }
    if (blob.contains('login') ||
        blob.contains('登录') ||
        blob.contains('sign in') ||
        blob.contains('new device') ||
        blob.contains('account recovery')) {
      return ConfirmationKind.login;
    }
    if (type == 1) return ConfirmationKind.login;
    return ConfirmationKind.other;
  }

  static ConfirmationRisk _mapRisk(int type) {
    return switch (type) {
      2 => ConfirmationRisk.high,
      3 || 5 => ConfirmationRisk.medium,
      _ => ConfirmationRisk.low,
    };
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _formatTime(int? unixSeconds) {
    if (unixSeconds == null || unixSeconds <= 0) return '刚刚';
    final created =
        DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true)
            .toLocal();
    final diff = DateTime.now().difference(created);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}
