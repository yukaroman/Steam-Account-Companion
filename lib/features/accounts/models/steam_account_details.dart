import '../../confirmations/domain/steam_mobile_session.dart';

/// Account details for the SteamTools-style info sheet.
///
/// Metadata is always safe to show. Secret fields are optional and only filled
/// after an explicit user reveal (personal-use product decision).
class SteamAccountDetails {
  const SteamAccountDetails({
    required this.accountId,
    required this.displayName,
    this.loginName,
    this.steamId64,
    this.serialNumber,
    this.deviceId,
    this.revocationCode,
    this.hasRevocationCode = false,
    this.hasIdentitySecret = false,
    this.hasSharedSecret = false,
    this.hasSteamPassword = false,
    this.hasMobileSession = false,
    this.sessionHealth = SteamSessionHealth.none,
    this.hasStoredSession = false,
    this.isDemo = false,
    this.sharedSecretBase64,
    this.identitySecretBase64,
    this.steamPassword,
    this.secretsRevealed = false,
  });

  final String accountId;
  final String displayName;
  final String? loginName;
  final String? steamId64;
  final String? serialNumber;
  final String? deviceId;

  /// Recovery code `R#####` — only set when [secretsRevealed] is true.
  final String? revocationCode;

  /// Whether a revocation code exists (safe to show as a status chip).
  final bool hasRevocationCode;

  final bool hasIdentitySecret;
  final bool hasSharedSecret;
  final bool hasSteamPassword;

  /// Usable session for live confirmations (active or refreshable).
  final bool hasMobileSession;

  /// JWT / cookie health for Session management UI.
  final SteamSessionHealth sessionHealth;

  /// Any session field stored (including expired) — enables “清除会话”.
  final bool hasStoredSession;

  final bool isDemo;

  /// Populated only when [secretsRevealed] is true.
  final String? sharedSecretBase64;
  final String? identitySecretBase64;
  final String? steamPassword;
  final bool secretsRevealed;

  String get confirmationCapabilityLabel =>
      hasIdentitySecret ? '可处理交易/登录确认' : '仅验证码（无 identity_secret）';

  String get sessionStatusLabel => sessionHealth.shortLabel;

  String get passwordStatusLabel {
    if (!hasSteamPassword) return '未导入';
    if (secretsRevealed && steamPassword != null) return steamPassword!;
    return '已保存（点下方查看）';
  }
}
