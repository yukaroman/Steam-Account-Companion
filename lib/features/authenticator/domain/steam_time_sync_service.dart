import '../../../core/network/steam_time_client.dart';
import 'time_provider.dart';

/// Applies Steam QueryTime to produce [SteamTimeSyncResult.serverTimeDiffMs].
///
/// Uses an RTT midpoint so network latency is not fully counted as clock skew
/// (request-start-only samples over-estimate how far behind the device is).
class SteamTimeSyncService {
  SteamTimeSyncService({
    required SteamTimeClient timeClient,
    required TimeProvider timeProvider,
    this.maxAcceptedRtt = const Duration(seconds: 5),
  })  : _timeClient = timeClient,
        _timeProvider = timeProvider;

  final SteamTimeClient _timeClient;
  final TimeProvider _timeProvider;

  /// Samples with longer RTT are rejected so a stalled request cannot skew codes.
  final Duration maxAcceptedRtt;

  Future<SteamTimeSyncResult> sync() async {
    final start = _timeProvider.now();
    final startMs = start.millisecondsSinceEpoch;

    final serverSeconds = await _timeClient.queryServerTimeSeconds();

    final end = _timeProvider.now();
    final endMs = end.millisecondsSinceEpoch;
    final rttMs = endMs >= startMs ? endMs - startMs : 0;

    if (rttMs > maxAcceptedRtt.inMilliseconds) {
      throw SteamTimeSyncRttException(
        rttMs: rttMs,
        maxMs: maxAcceptedRtt.inMilliseconds,
      );
    }

    // Midpoint of the round trip ≈ local time when the server stamped server_time.
    final midpointMs = startMs + (rttMs ~/ 2);
    // server_time is whole seconds; treat as that second's epoch ms (Steam convention).
    final serverMs = serverSeconds * 1000;
    final diffMs = serverMs - midpointMs;

    return SteamTimeSyncResult(
      serverTimeUnixSeconds: serverSeconds,
      serverTimeDiffMs: diffMs,
      syncedAt: end,
      localTimeMs: midpointMs,
    );
  }
}

/// Thrown when QueryTime RTT is too large to trust for clock offset.
class SteamTimeSyncRttException implements Exception {
  const SteamTimeSyncRttException({required this.rttMs, required this.maxMs});

  final int rttMs;
  final int maxMs;

  @override
  String toString() =>
      'SteamTimeSyncRttException(rttMs=$rttMs exceeds maxMs=$maxMs)';
}
