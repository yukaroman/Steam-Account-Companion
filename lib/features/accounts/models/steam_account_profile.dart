/// Non-secret account metadata safe to pass into presentation layers.
///
/// Only UI-facing fields belong here. Device identity (`deviceId`, serial),
/// Steam IDs, raw account names, secrets, cookies, and tokens must live in
/// [SteamAccountPrivateMeta] / [SteamAccountSecrets] instead.
class SteamAccountProfile {
  const SteamAccountProfile({
    required this.id,
    required this.nickname,
    required this.loginNameHint,
    required this.initials,
    required this.avatarColorValue,
  });

  /// Internal random / stable id (not a Steam device id).
  final String id;
  final String nickname;

  /// Full login / account name shown under the nickname (not masked).
  final String loginNameHint;
  final String initials;

  /// ARGB color as `0xAARRGGBB` so domain code stays free of Flutter types.
  final int avatarColorValue;

  SteamAccountProfile copyWith({
    String? id,
    String? nickname,
    String? loginNameHint,
    String? initials,
    int? avatarColorValue,
  }) {
    return SteamAccountProfile(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      loginNameHint: loginNameHint ?? this.loginNameHint,
      initials: initials ?? this.initials,
      avatarColorValue: avatarColorValue ?? this.avatarColorValue,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'nickname': nickname,
        'loginNameHint': loginNameHint,
        'initials': initials,
        'avatarColorValue': avatarColorValue,
      };

  factory SteamAccountProfile.fromJson(Map<String, Object?> json) {
    return SteamAccountProfile(
      id: json['id']! as String,
      nickname: json['nickname']! as String,
      loginNameHint: json['loginNameHint']! as String,
      initials: json['initials']! as String,
      avatarColorValue: json['avatarColorValue']! as int,
    );
  }
}
