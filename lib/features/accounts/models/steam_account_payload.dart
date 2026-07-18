import 'steam_account_private_meta.dart';
import 'steam_account_profile.dart';
import 'steam_account_secrets.dart';

/// Full plaintext account record before AES-GCM encryption.
///
/// Session fields will join this payload in a later batch.
class SteamAccountPayload {
  const SteamAccountPayload({
    required this.profile,
    required this.secrets,
    this.privateMeta = const SteamAccountPrivateMeta(),
    this.schemaVersion = currentSchemaVersion,
  });

  /// Schema 2 moves device identity out of presentation profiles.
  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final SteamAccountProfile profile;
  final SteamAccountPrivateMeta privateMeta;
  final SteamAccountSecrets secrets;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'profile': profile.toJson(),
        'privateMeta': privateMeta.toJson(),
        'secrets': secrets.toJson(),
      };

  factory SteamAccountPayload.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'] as int? ?? 1;
    if (version > currentSchemaVersion) {
      throw FormatException(
        'Unsupported account payload schemaVersion $version',
      );
    }

    final profileMap = Map<String, Object?>.from(json['profile']! as Map);
    final profile = SteamAccountProfile.fromJson(profileMap);

    final SteamAccountPrivateMeta privateMeta;
    if (json['privateMeta'] is Map) {
      privateMeta = SteamAccountPrivateMeta.fromJson(
        Map<String, Object?>.from(json['privateMeta'] as Map),
      );
    } else if (version <= 1) {
      privateMeta = SteamAccountPrivateMeta.fromLegacyProfileMap(profileMap);
    } else {
      privateMeta = const SteamAccountPrivateMeta();
    }

    return SteamAccountPayload(
      schemaVersion: version,
      profile: profile,
      privateMeta: privateMeta,
      secrets: SteamAccountSecrets.fromJson(
        Map<String, Object?>.from(json['secrets']! as Map),
      ),
    );
  }
}
