/// Sensitive identity metadata that must not reach presentation widgets.
///
/// Includes device identifiers and account identity fields used by import /
/// confirmation flows. Keep inside domain/infra only.
class SteamAccountPrivateMeta {
  const SteamAccountPrivateMeta({
    this.accountName,
    this.steamId64,
    this.serialNumber,
    this.deviceId,
  });

  final String? accountName;
  final String? steamId64;
  final String? serialNumber;

  /// Mobile device id (`android:{uuid}`) used by confirmation APIs.
  final String? deviceId;

  bool get isEmpty =>
      accountName == null &&
      steamId64 == null &&
      serialNumber == null &&
      deviceId == null;

  Map<String, Object?> toJson() => {
        if (accountName != null) 'accountName': accountName,
        if (steamId64 != null) 'steamId64': steamId64,
        if (serialNumber != null) 'serialNumber': serialNumber,
        if (deviceId != null) 'deviceId': deviceId,
      };

  factory SteamAccountPrivateMeta.fromJson(Map<String, Object?> json) {
    return SteamAccountPrivateMeta(
      accountName: json['accountName'] as String?,
      steamId64: json['steamId64'] as String?,
      serialNumber: json['serialNumber'] as String?,
      deviceId: json['deviceId'] as String?,
    );
  }

  /// Migrates fields that used to live on presentation profiles (schema v1).
  factory SteamAccountPrivateMeta.fromLegacyProfileMap(
    Map<String, Object?> profileJson,
  ) {
    return SteamAccountPrivateMeta(
      accountName: profileJson['accountName'] as String?,
      steamId64: profileJson['steamId64'] as String?,
      serialNumber: profileJson['serialNumber'] as String?,
      deviceId: profileJson['deviceId'] as String?,
    );
  }
}
