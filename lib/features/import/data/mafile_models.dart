/// Parsed SDA / SteamDesktopAuthenticator `.maFile` (and lightweight export) fields.
///
/// Secrets stay in this domain model only until [AccountImporter] encrypts them.
/// Supports classic maFile JSON and simplified account configs (e.g.
/// `steam_username` / `steam_password` + Guard secrets).
class MaFileData {
  const MaFileData({
    required this.sharedSecretBase64,
    this.identitySecretBase64,
    this.revocationCode,
    this.serialNumber,
    this.accountName,
    this.steamPassword,
    this.deviceId,
    this.steamId64,
    this.sessionId,
    this.steamLoginSecure,
    this.accessToken,
    this.refreshToken,
    this.uri,
    this.tokenGid,
    this.serverTime,
    this.fullyEnrolled,
  });

  final String sharedSecretBase64;
  final String? identitySecretBase64;
  final String? revocationCode;
  final String? serialNumber;
  final String? accountName;

  /// Plain Steam password when present in lightweight exports. Never UI-bound.
  final String? steamPassword;
  final String? deviceId;
  final String? steamId64;

  /// maFile `Session.SessionID` — community cookie for mobileconf.
  final String? sessionId;

  /// maFile `Session.SteamLoginSecure` cookie for authenticated community calls.
  final String? steamLoginSecure;

  /// Modern WinAuth / SteamTools JWT access token.
  final String? accessToken;

  /// Modern WinAuth / SteamTools JWT refresh token.
  final String? refreshToken;

  final String? uri;
  final String? tokenGid;
  final int? serverTime;
  final bool? fullyEnrolled;
}
