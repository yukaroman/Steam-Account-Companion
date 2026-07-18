/// Fetches Steam's two-factor service clock for Guard code alignment.
abstract interface class SteamTimeClient {
  /// Steam `server_time` in **Unix seconds**.
  Future<int> queryServerTimeSeconds();
}

/// Result of aligning local clock to Steam QueryTime.
class SteamTimeSyncResult {
  const SteamTimeSyncResult({
    required this.serverTimeUnixSeconds,
    required this.serverTimeDiffMs,
    required this.syncedAt,
    required this.localTimeMs,
  });

  final int serverTimeUnixSeconds;

  /// `serverNowMs - localNowMs` (same convention as WinAuth `ServerTimeDiff`).
  final int serverTimeDiffMs;

  final DateTime syncedAt;
  final int localTimeMs;
}
