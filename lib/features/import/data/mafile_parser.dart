import 'dart:convert';

import 'mafile_models.dart';

/// Parses Steam Desktop Authenticator / SteamTools / lightweight account JSON.
///
/// - Extra unknown keys are ignored (forward-compatible).
/// - Common key aliases and case variants are accepted.
/// - Never logs the source body.
///
/// Throws [MaFileParseException] on invalid input.
class MaFileParser {
  const MaFileParser();

  /// Parses one account. For multi-account documents use [parseAll].
  MaFileData parseString(String source) {
    final all = parseAll(source);
    if (all.length == 1) return all.single;
    // Back-compat: multi-account docs used to be rejected here. Callers that
    // only expect one account still get a clear error.
    throw MaFileParseException(
      'multi_account_document',
      'Document contains ${all.length} accounts — use batch import',
    );
  }

  /// Parses one or more accounts from a JSON document.
  ///
  /// Supported roots:
  /// - single maFile / lightweight account object
  /// - `{ "accounts": { "<steamid>": { ... }, ... }, "uuid_key": "android:..." }`
  /// - array of account objects
  List<MaFileData> parseAll(String source) {
    // Strip BOM / zero-width chars that break first-key matching after paste.
    var trimmed = source.trim();
    if (trimmed.startsWith('\uFEFF')) {
      trimmed = trimmed.substring(1).trim();
    }
    if (trimmed.isEmpty) {
      throw const MaFileParseException('empty_input', 'Import data is empty');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      throw const MaFileParseException(
          'invalid_json', 'File is not valid JSON');
    }

    if (decoded is List) {
      if (decoded.isEmpty) {
        throw const MaFileParseException(
          'empty_array',
          'JSON array has no accounts',
        );
      }
      final out = <MaFileData>[];
      for (var i = 0; i < decoded.length; i++) {
        final entry = decoded[i];
        if (entry is! Map) {
          throw MaFileParseException(
            'invalid_root',
            'Account entry #$i must be a JSON object',
          );
        }
        out.add(_parseMap(_unwrapAccountMap(Map<String, Object?>.from(entry))));
      }
      return out;
    }

    if (decoded is! Map) {
      throw const MaFileParseException(
        'invalid_root',
        'Root must be a JSON object or array of objects',
      );
    }

    final map = Map<String, Object?>.from(decoded);

    // Multi-account map used by some SteamTools-style exports:
    // { "accounts": { "7656...": { shared_secret, steamid, ... }, ... },
    //   "uuid_key": "android:..." }
    final multi = _extractAccountsMap(map);
    if (multi != null) {
      return multi;
    }

    return [_parseMap(_unwrapAccountMap(map))];
  }

  /// Returns parsed accounts when [map] is a multi-account container.
  List<MaFileData>? _extractAccountsMap(Map<String, Object?> map) {
    // Only treat as multi-account container when the root itself is not a
    // single maFile (no shared_secret at root).
    if (_hasSharedSecret(map)) return null;

    final accountsRaw = _readRaw(map, const [
      'accounts',
      'Accounts',
      'account_list',
      'accountList',
    ]);
    if (accountsRaw is! Map || accountsRaw.isEmpty) return null;

    final sharedDeviceId = _readString(map, const [
      'uuid_key',
      'uuidKey',
      'UUID_KEY',
      'device_id',
      'deviceId',
      'DeviceId',
      'DeviceID',
    ]);

    final out = <MaFileData>[];
    for (final entry in accountsRaw.entries) {
      final value = entry.value;
      if (value is! Map) {
        throw MaFileParseException(
          'invalid_account_entry',
          'accounts[${entry.key}] must be a JSON object',
        );
      }
      final accountMap = Map<String, Object?>.from(value);

      // Map key is often the SteamID64 when the body omits steamid.
      final keyId = entry.key.toString().trim();
      if (RegExp(r'^\d{15,20}$').hasMatch(keyId)) {
        final existing = _stringifyId(
          _readRaw(accountMap, const [
            'steamid',
            'SteamID',
            'steamId',
            'steam_id',
            'steamId64',
          ]),
        );
        if (existing == null || existing.isEmpty) {
          accountMap['steamid'] = keyId;
        }
      }

      // Root uuid_key applies to every account when they lack device_id.
      if (sharedDeviceId != null &&
          sharedDeviceId.isNotEmpty &&
          _readString(accountMap, const [
                'device_id',
                'deviceId',
                'DeviceId',
                'DeviceID',
              ]) ==
              null) {
        accountMap['device_id'] = sharedDeviceId;
      }

      out.add(_parseMap(_unwrapAccountMap(accountMap)));
    }

    if (out.isEmpty) {
      throw const MaFileParseException(
        'empty_accounts',
        'accounts map has no valid account objects',
      );
    }
    return out;
  }

  static bool _hasSharedSecret(Map<String, Object?> map) {
    return _readRaw(map, const [
          'shared_secret',
          'sharedSecret',
          'SharedSecret',
        ]) !=
        null;
  }

  /// Pulls the account object out of common wrappers
  /// (`maFile` / `SteamGuard` / `account` / nested JSON strings).
  static Map<String, Object?> _unwrapAccountMap(Map<String, Object?> map) {
    // If shared_secret is already here, use as-is.
    if (_readRaw(map, const [
          'shared_secret',
          'sharedSecret',
          'SharedSecret',
        ]) !=
        null) {
      return map;
    }

    for (final key in const [
      'maFile',
      'mafile',
      'MaFile',
      'steamguard',
      'SteamGuard',
      'steam_guard',
      'account',
      'Account',
      'data',
      'Data',
      'payload',
      'Authenticator',
      'authenticator',
    ]) {
      final nested = map[key];
      if (nested is Map) {
        final asMap = Map<String, Object?>.from(nested);
        if (_readRaw(asMap, const [
              'shared_secret',
              'sharedSecret',
              'SharedSecret',
            ]) !=
            null) {
          // Keep outer non-secret fields (e.g. steam_username) as fallback.
          return {...map, ...asMap};
        }
      }
      if (nested is String && nested.trim().startsWith('{')) {
        try {
          final decoded = jsonDecode(nested);
          if (decoded is Map) {
            final asMap = Map<String, Object?>.from(decoded);
            if (_readRaw(asMap, const [
                  'shared_secret',
                  'sharedSecret',
                  'SharedSecret',
                ]) !=
                null) {
              return {...map, ...asMap};
            }
          }
        } catch (_) {
          // ignore nested parse errors
        }
      }
    }
    return map;
  }

  MaFileData _parseMap(Map<String, Object?> map) {
    final shared = _readString(map, const [
      'shared_secret',
      'sharedSecret',
      'SharedSecret',
      'shared_secret_b64',
      'sharedSecretB64',
    ]);
    if (shared == null || shared.isEmpty) {
      throw const MaFileParseException(
        'missing_shared_secret',
        'shared_secret is required',
      );
    }

    // Validate Base64 early without keeping decoded bytes longer than needed.
    try {
      base64.decode(_normalizeBase64(shared));
    } on FormatException {
      throw const MaFileParseException(
        'invalid_shared_secret',
        'shared_secret is not valid Base64',
      );
    }

    final identity = _readString(map, const [
      'identity_secret',
      'identitySecret',
      'IdentitySecret',
      'identity_secret_b64',
      'identitySecretB64',
    ]);
    if (identity != null && identity.isNotEmpty) {
      try {
        base64.decode(_normalizeBase64(identity));
      } on FormatException {
        throw const MaFileParseException(
          'invalid_identity_secret',
          'identity_secret is not valid Base64',
        );
      }
    }

    // Session may be a map or a JSON-encoded string.
    Map<String, Object?>? session = _readMap(map, const ['Session', 'session']);
    if (session == null) {
      final rawSession = _readRaw(map, const ['Session', 'session']);
      if (rawSession is String && rawSession.trim().startsWith('{')) {
        try {
          final decoded = jsonDecode(rawSession);
          if (decoded is Map) {
            session = Map<String, Object?>.from(decoded);
          }
        } catch (_) {}
      }
    }

    String? steamIdFromSession;
    String? sessionId;
    String? steamLoginSecure;
    String? accessToken;
    String? refreshToken;
    if (session != null) {
      steamIdFromSession = _stringifyId(
        _readRaw(session, const [
          'SteamID',
          'steamid',
          'SteamId',
          'steam_id',
          'steamId64',
          'SteamId64',
        ]),
      );
      sessionId = _readString(session, const [
        'SessionID',
        'sessionId',
        'session_id',
        'SessionId',
        'sessionid',
      ]);
      steamLoginSecure = _readString(session, const [
        'SteamLoginSecure',
        'steamLoginSecure',
        'steam_login_secure',
        // Do not map SteamLogin here — classic SDA SteamLogin is not the
        // secure cookie; prefer AccessToken / SteamLoginSecure only.
      ]);
      accessToken = _readString(session, const [
        'AccessToken',
        'accessToken',
        'access_token',
        'OAuthToken',
        'oAuthToken',
        'oauth_token',
      ]);
      refreshToken = _readString(session, const [
        'RefreshToken',
        'refreshToken',
        'refresh_token',
      ]);
      // Nested cookie blob inside Session.
      final sessionCookies = _readString(session, const [
        'cookies',
        'Cookies',
        'WebCookie',
        'Cookie',
      ]);
      if (sessionCookies != null) {
        sessionId ??= _cookieValue(sessionCookies, 'sessionid');
        steamLoginSecure ??= _cookieValue(sessionCookies, 'steamLoginSecure');
      }
    }

    // Some lightweight exports put cookies at the root.
    sessionId ??= _readString(map, const [
      'SessionID',
      'sessionId',
      'session_id',
      'sessionid',
    ]);
    steamLoginSecure ??= _readString(map, const [
      'SteamLoginSecure',
      'steamLoginSecure',
      'steam_login_secure',
    ]);
    accessToken ??= _readString(map, const [
      'AccessToken',
      'accessToken',
      'access_token',
      'OAuthToken',
    ]);
    refreshToken ??= _readString(map, const [
      'RefreshToken',
      'refreshToken',
      'refresh_token',
    ]);

    // Cookie header style: "sessionid=...; steamLoginSecure=..."
    final cookieBlob = _readString(map, const [
      'cookies',
      'Cookies',
      'cookie',
      'Cookie',
      'WebCookie',
      'webCookie',
      'SteamCookies',
      'steam_cookies',
    ]);
    if (cookieBlob != null) {
      sessionId ??= _cookieValue(cookieBlob, 'sessionid');
      steamLoginSecure ??= _cookieValue(cookieBlob, 'steamLoginSecure');
    }

    var deviceId = _readString(map, const [
      'device_id',
      'deviceId',
      'DeviceId',
      'DeviceID',
      'deviceid',
      'Device_Id',
    ]);
    // Soft-accept non-android formats (SDA prefers android:{uuid}).
    // Some tools store device id only inside Session.
    deviceId ??= session == null
        ? null
        : _readString(session, const [
            'device_id',
            'deviceId',
            'DeviceId',
            'DeviceID',
          ]);

    final accountName = _readString(map, const [
      'account_name',
      'accountName',
      'AccountName',
      'steam_username',
      'steamUsername',
      'SteamUsername',
      'username',
      'user_name',
      'userName',
      'login',
      'login_name',
      'loginName',
    ]);

    final steamPassword = _readString(map, const [
      'steam_password',
      'steamPassword',
      'SteamPassword',
      'password',
      'Password',
      'account_password',
      'accountPassword',
    ]);

    var steamId64 = _stringifyId(
          _readRaw(map, const [
            'steamid',
            'SteamID',
            'steamId',
            'steam_id',
            'steamId64',
            'steam_id64',
            'SteamId64',
            'steamid64',
          ]),
        ) ??
        steamIdFromSession;

    // steamLoginSecure is often "{steamId}||{token}" or URL-encoded.
    steamId64 ??= _steamIdFromLoginSecure(steamLoginSecure);

    // Modern exports may only have AccessToken; mobileconf still expects
    // steamLoginSecure cookie shape: "{steamId}%7C%7C{token}" (WinAuth).
    if ((steamLoginSecure == null || steamLoginSecure.isEmpty) &&
        accessToken != null &&
        accessToken.isNotEmpty &&
        steamId64 != null &&
        steamId64.isNotEmpty) {
      steamLoginSecure = '$steamId64%7C%7C$accessToken';
    }

    // Last resort: some incomplete tokens only ship access token without steamId.
    // Still not enough for confirmations without steamId + sessionid.

    return MaFileData(
      sharedSecretBase64: _normalizeBase64(shared),
      identitySecretBase64: identity == null || identity.isEmpty
          ? null
          : _normalizeBase64(identity),
      revocationCode: _readString(map, const [
        'revocation_code',
        'revocationCode',
        'RevocationCode',
      ]),
      serialNumber: _readString(map, const [
        'serial_number',
        'serialNumber',
        'SerialNumber',
      ]),
      accountName: accountName,
      steamPassword: steamPassword,
      deviceId: deviceId,
      steamId64: steamId64,
      sessionId: sessionId,
      steamLoginSecure: steamLoginSecure,
      accessToken: accessToken,
      refreshToken: refreshToken,
      uri: _readString(map, const ['uri', 'Uri', 'URI']),
      tokenGid: _readString(map, const ['token_gid', 'tokenGid', 'TokenGid']),
      serverTime: _readInt(
        _readRaw(map, const ['server_time', 'serverTime', 'ServerTime']),
      ),
      fullyEnrolled: _readBool(
        _readRaw(
            map, const ['fully_enrolled', 'fullyEnrolled', 'FullyEnrolled']),
      ),
    );
  }

  MaFileData parseBytes(List<int> bytes) {
    return parseString(utf8.decode(bytes));
  }

  /// Reads the first non-empty string for any of [keys].
  ///
  /// Matching order: exact key → case-insensitive → alphanumeric-normalized
  /// (`steam_username` / `SteamUsername` / `steam-username` all match).
  static String? _readString(Map<String, Object?> map, List<String> keys) {
    final raw = _readRaw(map, keys);
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Object? _readRaw(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key)) {
        final value = map[key];
        if (value != null) return value;
      }
    }

    final lowerIndex = <String, String>{};
    final compactIndex = <String, String>{};
    for (final existing in map.keys) {
      final asString = existing.toString();
      lowerIndex.putIfAbsent(asString.toLowerCase(), () => asString);
      compactIndex.putIfAbsent(_compactKey(asString), () => asString);
    }

    for (final key in keys) {
      final byLower = lowerIndex[key.toLowerCase()];
      if (byLower != null) {
        final value = map[byLower];
        if (value != null) return value;
      }
      final byCompact = compactIndex[_compactKey(key)];
      if (byCompact != null) {
        final value = map[byCompact];
        if (value != null) return value;
      }
    }
    return null;
  }

  /// `steam_username` / `Steam-Username` / `steamUsername` → `steamusername`
  static String _compactKey(String key) {
    return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static Map<String, Object?>? _readMap(
    Map<String, Object?> map,
    List<String> keys,
  ) {
    final raw = _readRaw(map, keys);
    if (raw is Map) {
      return Map<String, Object?>.from(raw);
    }
    return null;
  }

  static int? _readInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static bool? _readBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return null;
  }

  static String? _stringifyId(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String _normalizeBase64(String value) {
    final trimmed = value.trim();
    final remainder = trimmed.length % 4;
    if (remainder == 0) return trimmed;
    return trimmed.padRight(trimmed.length + (4 - remainder), '=');
  }

  /// Extracts a cookie value from a `name=value; name2=value2` blob.
  static String? _cookieValue(String cookieHeader, String name) {
    final parts = cookieHeader.split(RegExp(r';\s*'));
    final lower = name.toLowerCase();
    for (final part in parts) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final key = part.substring(0, idx).trim().toLowerCase();
      if (key != lower) continue;
      final value = part.substring(idx + 1).trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// Parses steamId from `steamLoginSecure` cookie value.
  static String? _steamIdFromLoginSecure(String? loginSecure) {
    if (loginSecure == null || loginSecure.isEmpty) return null;
    final decoded =
        loginSecure.contains('%7C%7C') || loginSecure.contains('%7c%7c')
            ? Uri.decodeComponent(loginSecure)
            : loginSecure;
    final parts = decoded.split('||');
    if (parts.isEmpty) return null;
    final id = parts.first.trim();
    if (RegExp(r'^\d{15,20}$').hasMatch(id)) return id;
    return null;
  }
}

class MaFileParseException implements Exception {
  const MaFileParseException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'MaFileParseException($code): $message';
}
