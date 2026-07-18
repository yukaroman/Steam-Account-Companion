import 'dart:convert';
import 'dart:typed_data';

/// Sensitive Steam Guard material (and optional login password). Stay inside
/// domain/infra only.
///
/// Presentation widgets must never receive this type.
class SteamAccountSecrets {
  SteamAccountSecrets({
    required List<int> sharedSecret,
    List<int>? identitySecret,
    this.revocationCode,
    this.steamPassword,
    this.sessionId,
    this.steamLoginSecure,
    this.accessToken,
    this.refreshToken,
  })  : sharedSecret = Uint8List.fromList(sharedSecret),
        identitySecret =
            identitySecret == null ? null : Uint8List.fromList(identitySecret);

  /// Raw `shared_secret` bytes (Base64-decoded maFile field).
  final Uint8List sharedSecret;

  /// Raw `identity_secret` bytes used later for confirmation hashes.
  final Uint8List? identitySecret;

  /// Recovery / revocation code (`R#####`), if present.
  final String? revocationCode;

  /// Steam account password from lightweight exports. Never pass to UI.
  final String? steamPassword;

  /// Community session id cookie (`sessionid`) for mobileconf.
  ///
  /// Optional for modern JWT sessions — WinAuth generates one when missing.
  final String? sessionId;

  /// `steamLoginSecure` cookie from maFile Session (or derived from tokens).
  final String? steamLoginSecure;

  /// Modern JWT access token (SteamTools / WinAuth `access_token`).
  final String? accessToken;

  /// Modern JWT refresh token for [GenerateAccessTokenForApp].
  final String? refreshToken;

  /// True when secrets can form mobileconf cookies (classic cookies **or** JWT).
  ///
  /// `sessionid` is not required: it can be generated locally (WinAuth).
  /// SteamId for minting `steamLoginSecure` from access token alone lives in
  /// private meta and is checked by the confirmations repository.
  bool get hasMobileSession {
    final hasSecure =
        steamLoginSecure != null && steamLoginSecure!.trim().isNotEmpty;
    final hasToken = accessToken != null && accessToken!.trim().isNotEmpty;
    return hasSecure || hasToken;
  }

  factory SteamAccountSecrets.fromBase64({
    required String sharedSecretBase64,
    String? identitySecretBase64,
    String? revocationCode,
    String? steamPassword,
    String? sessionId,
    String? steamLoginSecure,
    String? accessToken,
    String? refreshToken,
  }) {
    return SteamAccountSecrets(
      sharedSecret: base64.decode(_normalizeBase64(sharedSecretBase64)),
      identitySecret: identitySecretBase64 == null
          ? null
          : base64.decode(_normalizeBase64(identitySecretBase64)),
      revocationCode: revocationCode,
      steamPassword: steamPassword,
      sessionId: sessionId,
      steamLoginSecure: steamLoginSecure,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  SteamAccountSecrets copyWith({
    List<int>? sharedSecret,
    List<int>? identitySecret,
    String? revocationCode,
    String? steamPassword,
    bool clearSteamPassword = false,
    String? sessionId,
    String? steamLoginSecure,
    String? accessToken,
    String? refreshToken,
  }) {
    return SteamAccountSecrets(
      sharedSecret: sharedSecret ?? this.sharedSecret,
      identitySecret: identitySecret ?? this.identitySecret,
      revocationCode: revocationCode ?? this.revocationCode,
      steamPassword:
          clearSteamPassword ? null : (steamPassword ?? this.steamPassword),
      sessionId: sessionId ?? this.sessionId,
      steamLoginSecure: steamLoginSecure ?? this.steamLoginSecure,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  /// Drops Session cookies/tokens; keeps Guard secrets.
  ///
  /// When [clearSavedPassword] is true, also removes stored Steam password.
  SteamAccountSecrets withoutSession({bool clearSavedPassword = false}) {
    return SteamAccountSecrets(
      sharedSecret: sharedSecret,
      identitySecret: identitySecret,
      revocationCode: revocationCode,
      steamPassword: clearSavedPassword ? null : steamPassword,
      sessionId: null,
      steamLoginSecure: null,
      accessToken: null,
      refreshToken: null,
    );
  }

  Map<String, Object?> toJson() => {
        'sharedSecretB64': base64.encode(sharedSecret),
        if (identitySecret != null)
          'identitySecretB64': base64.encode(identitySecret!),
        if (revocationCode != null) 'revocationCode': revocationCode,
        if (steamPassword != null) 'steamPassword': steamPassword,
        if (sessionId != null) 'sessionId': sessionId,
        if (steamLoginSecure != null) 'steamLoginSecure': steamLoginSecure,
        if (accessToken != null) 'accessToken': accessToken,
        if (refreshToken != null) 'refreshToken': refreshToken,
      };

  factory SteamAccountSecrets.fromJson(Map<String, Object?> json) {
    return SteamAccountSecrets.fromBase64(
      sharedSecretBase64: json['sharedSecretB64']! as String,
      identitySecretBase64: json['identitySecretB64'] as String?,
      revocationCode: json['revocationCode'] as String?,
      steamPassword: json['steamPassword'] as String?,
      sessionId: json['sessionId'] as String?,
      steamLoginSecure: json['steamLoginSecure'] as String?,
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
    );
  }

  static String _normalizeBase64(String value) {
    final trimmed = value.trim();
    final remainder = trimmed.length % 4;
    if (remainder == 0) return trimmed;
    return trimmed.padRight(trimmed.length + (4 - remainder), '=');
  }
}
