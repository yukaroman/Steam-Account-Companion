import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import '../domain/steam_login_result.dart';
import 'steam_auth_protobuf.dart';

/// Steam Auth V2 password login (personal-use, unofficial).
///
/// Flow aligned with SteamTools `DoLoginV2Async` / steampy protobuf login:
/// RSA key → BeginAuthSessionViaCredentials → (Guard code) → Poll tokens.
class SteamLoginClient {
  SteamLoginClient({
    http.Client? httpClient,
    this.userAgent = _defaultUserAgent,
    this.timeout = const Duration(seconds: 25),
    this.maxAttempts = 3,
  }) : _http = httpClient ?? http.Client();

  /// Match Steam community mobile web UA (SteamTools-style).
  static const _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const _apiBase = 'https://api.steampowered.com/IAuthenticationService';

  final http.Client _http;
  final String userAgent;
  final Duration timeout;
  final int maxAttempts;

  /// Full login. When [twoFactorCode] / [emailCode] are null and Steam requires
  /// them, returns [SteamLoginNeedsGuard] so the caller can supply codes.
  Future<SteamLoginClientResult> login({
    required String username,
    required String password,
    String? twoFactorCode,
    String? emailCode,
    bool rememberLogin = true,
  }) async {
    // Prefill / paste often includes BOM, NBSP, zero-width chars, or mixed case.
    // First-tap login with a "default" username failed with EResult 9 for users
    // until they re-typed the same name — normalize aggressively before Steam.
    final account = sanitizeSteamAccountName(username);
    final pass = sanitizeSteamPassword(password);
    if (account.isEmpty || pass.isEmpty) {
      return const SteamLoginFailed(
        '请填写完整的 Steam 登录名和密码（不要使用昵称）',
      );
    }

    try {
      final rsa = await _getRsaKey(account);
      final encrypted = encryptPasswordRsa(
        password: pass,
        modHex: rsa.publicKeyModHex,
        expHex: rsa.publicKeyExpHex,
      );

      final begin = await _beginAuthSession(
        accountName: account,
        encryptedPasswordBase64: encrypted,
        encryptionTimestamp: rsa.timestamp,
        rememberLogin: rememberLogin,
      );

      if (begin.steamId == 0 || begin.clientId == 0) {
        return const SteamLoginFailed(
          '请核对您的密码和账户名称并重试',
          code: 'bad_credentials',
        );
      }

      final clientId = begin.clientId;
      final requestId = begin.requestId;
      final steamId = begin.steamId;

      if (begin.needsDeviceCode) {
        final code = twoFactorCode?.trim() ?? '';
        if (code.isEmpty) {
          return SteamLoginNeedsGuard(
            kind: SteamLoginGuardKind.deviceCode,
            clientId: clientId,
            requestId: requestId,
            steamId: steamId,
          );
        }
        // Brief pause so Steam can register the auth session before Guard update.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await _updateGuardCode(
          clientId: clientId,
          steamId: steamId,
          code: code,
          codeType: SteamAuthProtobuf.guardDeviceCode,
        );
      } else if (begin.needsEmailCode) {
        final code = emailCode?.trim() ?? '';
        if (code.isEmpty) {
          // SteamTools: trigger email delivery before asking the user.
          await _checkDevice(clientId: clientId, steamId: steamId);
          return SteamLoginNeedsGuard(
            kind: SteamLoginGuardKind.emailCode,
            clientId: clientId,
            requestId: requestId,
            steamId: steamId,
            emailHint: begin.emailHint,
          );
        }
        await _updateGuardCode(
          clientId: clientId,
          steamId: steamId,
          code: code,
          codeType: SteamAuthProtobuf.guardEmailCode,
        );
      } else if (begin.needsDeviceConfirmation ||
          begin.needsEmailConfirmation) {
        // User must approve on Steam Mobile / email; poll for tokens.
        final tokens = await _pollTokensWithRetry(
          clientId: clientId,
          requestId: requestId,
          attempts: 12,
        );
        if (tokens.hasTokens) {
          return SteamLoginSuccess(
            steamId64: steamId.toString(),
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
          );
        }
        return SteamLoginFailed(
          begin.needsDeviceConfirmation
              ? '请在已登录的 Steam 手机 App 上确认此次登录，然后重试'
              : '请在邮箱中确认此次登录，然后重试',
          code: 'needs_remote_confirmation',
        );
      }

      final tokens = await _pollTokensWithRetry(
        clientId: clientId,
        requestId: requestId,
      );
      if (!tokens.hasTokens) {
        return const SteamLoginFailed(
          '登录未完成：验证码可能不正确，或 Steam 需要稍后再试',
          code: 'no_tokens',
        );
      }

      return SteamLoginSuccess(
        steamId64: steamId.toString(),
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } on SteamLoginException catch (e) {
      return SteamLoginFailed(e.message, code: e.code);
    } on TimeoutException {
      return const SteamLoginFailed('登录超时，请检查网络后重试', code: 'timeout');
    } on SocketException catch (e) {
      return SteamLoginFailed(
        '无法连接 Steam（${e.message}）。请确认网络可访问 api.steampowered.com',
        code: 'socket',
      );
    } on HandshakeException {
      return const SteamLoginFailed(
        '与 Steam 建立安全连接失败，请切换网络或稍后重试',
        code: 'tls',
      );
    } catch (e) {
      return SteamLoginFailed(
        '登录失败：${_shortError(e)}',
        code: 'unexpected',
      );
    }
  }

  /// Continues after [SteamLoginNeedsGuard] with a Guard / email code.
  Future<SteamLoginClientResult> continueWithGuardCode({
    required int clientId,
    required List<int> requestId,
    required int steamId,
    required SteamLoginGuardKind kind,
    required String code,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const SteamLoginFailed('请输入验证码');
    }
    try {
      await _updateGuardCode(
        clientId: clientId,
        steamId: steamId,
        code: trimmed,
        codeType: kind == SteamLoginGuardKind.deviceCode
            ? SteamAuthProtobuf.guardDeviceCode
            : SteamAuthProtobuf.guardEmailCode,
      );
      final tokens = await _pollTokensWithRetry(
        clientId: clientId,
        requestId: requestId,
      );
      if (!tokens.hasTokens) {
        return const SteamLoginFailed(
          '登录未完成：验证码可能不正确，请稍后重试',
          code: 'no_tokens',
        );
      }
      return SteamLoginSuccess(
        steamId64: steamId.toString(),
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } on SteamLoginException catch (e) {
      return SteamLoginFailed(e.message, code: e.code);
    } on TimeoutException {
      return const SteamLoginFailed('登录超时，请检查网络后重试', code: 'timeout');
    } on SocketException catch (e) {
      return SteamLoginFailed(
        '无法连接 Steam（${e.message}）',
        code: 'socket',
      );
    } on HandshakeException {
      return const SteamLoginFailed(
        '与 Steam 建立安全连接失败，请切换网络或稍后重试',
        code: 'tls',
      );
    } catch (e) {
      return SteamLoginFailed(
        '登录失败：${_shortError(e)}',
        code: 'unexpected',
      );
    }
  }

  Future<RsaPublicKeyResponse> _getRsaKey(String accountName) async {
    final encoded = SteamAuthProtobuf.encodeGetPasswordRsaRequest(
      accountName: accountName,
    );
    final uri = Uri.parse(
      '$_apiBase/GetPasswordRSAPublicKey/v1/',
    ).replace(queryParameters: {'input_protobuf_encoded': encoded});

    final response = await _send(() => _http.get(uri, headers: _headers()));
    _ensureOk(response, action: '获取登录密钥');
    if (response.bodyBytes.isEmpty) {
      throw SteamLoginException('获取登录密钥失败：空响应', code: 'empty_rsa');
    }
    return SteamAuthProtobuf.decodeGetPasswordRsaResponse(response.bodyBytes);
  }

  Future<BeginAuthSessionResponse> _beginAuthSession({
    required String accountName,
    required String encryptedPasswordBase64,
    required int encryptionTimestamp,
    required bool rememberLogin,
  }) async {
    final encoded = SteamAuthProtobuf.encodeBeginAuthSessionRequest(
      deviceFriendlyName: userAgent,
      accountName: accountName,
      encryptedPasswordBase64: encryptedPasswordBase64,
      encryptionTimestamp: encryptionTimestamp,
      rememberLogin: rememberLogin,
    );
    final response = await _send(
      () => _http.post(
        Uri.parse('$_apiBase/BeginAuthSessionViaCredentials/v1/'),
        headers: {
          ..._headers(),
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: {'input_protobuf_encoded': encoded},
      ),
    );

    final eResult = _eresult(response);
    // Steam often returns HTTP 200 with x-eresult=5 and empty body for bad password.
    if (eResult != null && eResult != '1' && eResult != '0') {
      throw SteamLoginException(
        _errorMessage(response, eResult) ?? '登录失败（$eResult）',
        code: 'begin_eresult_$eResult',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SteamLoginException(
        _errorMessage(response, eResult) ?? '登录失败（HTTP ${response.statusCode}）',
        code: 'http_${response.statusCode}',
      );
    }

    if (response.bodyBytes.isEmpty) {
      throw SteamLoginException(
        _errorMessage(response, eResult) ?? '请核对您的密码和账户名称并重试',
        code: 'bad_credentials',
      );
    }

    final begin =
        SteamAuthProtobuf.decodeBeginAuthSessionResponse(response.bodyBytes);
    if (begin.steamId == 0 || begin.clientId == 0) {
      throw SteamLoginException(
        _errorMessage(response, eResult) ?? '请核对您的密码和账户名称并重试',
        code: 'bad_credentials',
      );
    }
    return begin;
  }

  /// SteamTools `jwt/checkdevice` — asks Steam to send the email Guard code.
  Future<void> _checkDevice({
    required int clientId,
    required int steamId,
  }) async {
    final response = await _send(
      () => _http.post(
        Uri.parse('https://login.steampowered.com/jwt/checkdevice/'),
        headers: {
          ..._headers(),
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: {
          'clientid': clientId.toString(),
          'steamid': steamId.toString(),
        },
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SteamLoginException(
        '无法请求邮箱验证码（HTTP ${response.statusCode}）',
        code: 'checkdevice_http_${response.statusCode}',
      );
    }
    final body = response.body.trim().toLowerCase();
    // Steam may return HTML or tiny JSON; hard failures usually non-2xx.
    // Empty body is accepted (SteamTools does not require a strict body).
    if (body.contains('error') && body.contains('false') == false) {
      // Soft signal only; still proceed to UI so user can retry / enter code.
    }
  }

  Future<void> _updateGuardCode({
    required int clientId,
    required int steamId,
    required String code,
    required int codeType,
  }) async {
    final encoded = SteamAuthProtobuf.encodeUpdateGuardCodeRequest(
      clientId: clientId,
      steamId: steamId,
      // Steam Guard device codes are uppercase A-Z / 2-9.
      code: code.trim().toUpperCase(),
      codeType: codeType,
    );
    final response = await _send(
      () => _http.post(
        Uri.parse('$_apiBase/UpdateAuthSessionWithSteamGuardCode/v1/'),
        headers: {
          ..._headers(),
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: {'input_protobuf_encoded': encoded},
      ),
    );
    final eResult = _eresult(response);
    // steampy ignores eresult 29 (duplicate request / already updated).
    if (eResult != null &&
        eResult != '1' &&
        eResult != '0' &&
        eResult != '29') {
      throw SteamLoginException(
        _errorMessage(response, eResult) ?? '提交验证码失败（$eResult）',
        code: 'guard_eresult_$eResult',
      );
    }
    if (response.statusCode >= 500) {
      throw SteamLoginException(
        '提交验证码失败（HTTP ${response.statusCode}）',
        code: 'guard_failed',
      );
    }
  }

  Future<PollAuthSessionResponse> _pollTokensWithRetry({
    required int clientId,
    required List<int> requestId,
    int attempts = 6,
  }) async {
    PollAuthSessionResponse? last;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) {
        await Future<void>.delayed(Duration(milliseconds: 800 * i));
      }
      last = await _pollTokens(clientId: clientId, requestId: requestId);
      if (last.hasTokens) return last;
    }
    return last ??
        const PollAuthSessionResponse(accessToken: '', refreshToken: '');
  }

  Future<PollAuthSessionResponse> _pollTokens({
    required int clientId,
    required List<int> requestId,
  }) async {
    final encoded = SteamAuthProtobuf.encodePollAuthSessionRequest(
      clientId: clientId,
      requestId: requestId,
    );
    final response = await _send(
      () => _http.post(
        Uri.parse('$_apiBase/PollAuthSessionStatus/v1/'),
        headers: {
          ..._headers(),
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: {'input_protobuf_encoded': encoded},
      ),
    );
    _ensureOk(response, action: '确认登录状态');
    if (response.bodyBytes.isEmpty) {
      return const PollAuthSessionResponse(accessToken: '', refreshToken: '');
    }
    return SteamAuthProtobuf.decodePollAuthSessionResponse(response.bodyBytes);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await request().timeout(timeout);
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on HandshakeException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    final err = lastError;
    if (err is TimeoutException) throw err;
    if (err is SocketException) throw err;
    if (err is HandshakeException) throw err;
    throw SteamLoginException(
      '网络请求失败：${_shortError(err ?? 'unknown')}',
      code: 'network',
    );
  }

  void _ensureOk(http.Response response, {required String action}) {
    final eResult = _eresult(response);
    if (eResult != null && eResult != '1' && eResult != '0') {
      throw SteamLoginException(
        _errorMessage(response, eResult) ?? '$action失败（$eResult）',
        code: 'eresult_$eResult',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SteamLoginException(
        _errorMessage(response, eResult) ??
            '$action失败（HTTP ${response.statusCode}）',
        code: 'http_${response.statusCode}',
      );
    }
  }

  Map<String, String> _headers() => {
        'User-Agent': userAgent,
        'Accept': 'application/x-protobuf, application/octet-stream, */*',
        'Origin': 'https://steamcommunity.com',
        'Referer': 'https://steamcommunity.com/',
      };

  static String? _eresult(http.Response response) {
    return response.headers['x-eresult'] ?? response.headers['X-eresult'];
  }

  /// Prefer Steam's `x-error_message` when present.
  static String? _errorMessage(http.Response response, String? eResult) {
    final steamMessage = response.headers['x-error_message'] ??
        response.headers['X-error_message'];
    if (steamMessage != null && steamMessage.trim().isNotEmpty) {
      return steamMessage.trim();
    }
    return _mapEResult(eResult);
  }

  static String? _mapEResult(String? eResult) {
    return switch (eResult) {
      '5' => '请核对您的密码和账户名称并重试',
      '8' => '登录参数被 Steam 拒绝（错误码 8）。请热重启/重装最新构建后重试',
      '9' => 'Steam 找不到该登录会话或账号（错误码 9）。请确认用户名是完整 Steam 账号名（不要用昵称/遮罩），并检查密码后重试',
      '15' || '25' => '该账号暂时无法登录，请稍后再试',
      '20' => '与 Steam 通信时出现问题，请稍后重试',
      '84' || '87' => '短时间内失败登录过多，请约 15 分钟后再试',
      '88' || '89' => '需要验证码，请稍后重试',
      '65' => '验证码不正确',
      null || '' || '1' || '0' => null,
      _ => '登录遇到问题（错误码 $eResult），请稍后重试',
    };
  }

  static String _shortError(Object e) {
    final s = e.toString();
    if (s.length <= 120) return s;
    return '${s.substring(0, 117)}...';
  }

  /// Normalize a Steam account name for Auth V2 login.
  ///
  /// Strips invisible noise, maps fullwidth/confusable ASCII (e.g. `＿` → `_`)
  /// so imported JSON / IME input that *looks* like `demo__login__name` is not
  /// silently turned into `demologinname`, then lowercases.
  static String sanitizeSteamAccountName(String value) {
    var text = value;
    // BOM / zero-width / word-joiner / NBSP → normal space then trim.
    text = text.replaceAll('\uFEFF', '');
    text = text.replaceAll(RegExp(r'[\u200B-\u200D\u2060\uFEFF]'), '');
    text = text.replaceAll('\u00A0', ' ');
    text = text.replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069]'), '');
    // Fullwidth Latin/punctuation (U+FF01–FF5E) → ASCII, including fullwidth `_`.
    text = fullwidthAsciiToHalfwidth(text);
    // Other underscore lookalikes sometimes seen in exports / paste.
    text = text
        .replaceAll('\u2017', '_') // double low line
        .replaceAll('\u02CD', '_') // modifier letter low macron
        .replaceAll('\uFF3F', '_'); // fullwidth low line (also covered above)
    text = text.trim();
    // Steam login names cannot contain spaces; remove residual whitespace.
    text = text.replaceAll(RegExp(r'\s+'), '');
    text = asciiOnly(text);
    return text.toLowerCase();
  }

  /// Strip clipboard noise from passwords without changing intentional spaces.
  static String sanitizeSteamPassword(String value) {
    var text = value;
    text = text.replaceAll('\uFEFF', '');
    text = text.replaceAll(RegExp(r'[\u200B-\u200D\u2060\uFEFF]'), '');
    text = text.replaceAll('\u00A0', ' ');
    // Trailing CR/LF from paste into “记住密码” is a common silent failure.
    text = text.replaceAll(RegExp(r'[\r\n]+$'), '');
    // Map fullwidth Latin so pasted passwords with fullwidth chars still work.
    text = fullwidthAsciiToHalfwidth(text);
    return asciiOnly(text);
  }

  /// Steam strips non-ASCII from username/password fields.
  static String asciiOnly(String value) {
    return value.replaceAll(RegExp(r'[^\u0000-\u007F]'), '');
  }

  /// Maps fullwidth ASCII forms (common with CJK IME / some JSON exports) to halfwidth.
  ///
  /// U+FF01–U+FF5E ↔ U+0021–U+007E (includes fullwidth underscore U+FF3F → `_`).
  static String fullwidthAsciiToHalfwidth(String value) {
    final buffer = StringBuffer();
    for (final unit in value.runes) {
      if (unit >= 0xFF01 && unit <= 0xFF5E) {
        buffer.writeCharCode(unit - 0xFEE0);
      } else if (unit == 0x3000) {
        buffer.writeCharCode(0x20); // ideographic space → space
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  /// RSA PKCS#1 v1.5 encrypt password; returns standard Base64 ciphertext.
  static String encryptPasswordRsa({
    required String password,
    required String modHex,
    required String expHex,
  }) {
    final modulus = BigInt.parse(modHex, radix: 16);
    final exponent = BigInt.parse(expHex, radix: 16);
    final key = RSAPublicKey(modulus, exponent);
    final engine = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(key));
    // Steam encrypts the ASCII password bytes (not UTF-16).
    final input = Uint8List.fromList(ascii.encode(password));
    final encrypted = engine.process(input);
    return base64.encode(encrypted);
  }
}
