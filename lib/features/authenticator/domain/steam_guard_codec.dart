import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Pure Steam Guard TOTP helpers.
///
/// Algorithm matches the mobile Steam Guard / WinAuth lineage used by Watt
/// Toolkit: HMAC-SHA1 over a 30s counter, truncated to five characters from
/// [steamChars]. This type has no I/O and never logs secrets.
abstract final class SteamGuardCodec {
  /// Steam alphabet (26 chars). Visually ambiguous glyphs are omitted.
  static const steamChars = '23456789BCDFGHJKMNPQRTVWXY';

  static const int periodSeconds = 30;
  static const int codeDigits = 5;
  static const int _periodMs = periodSeconds * 1000;

  /// Builds the five-character code for [sharedSecret] at [now].
  ///
  /// [serverTimeDiffMs] is `serverNowMs - localNowMs`, matching WinAuth's
  /// `ServerTimeDiff` after `ITwoFactorService/QueryTime`.
  static String codeFromSharedSecret({
    required List<int> sharedSecret,
    required DateTime now,
    int serverTimeDiffMs = 0,
  }) {
    if (sharedSecret.isEmpty) {
      throw ArgumentError.value(
          sharedSecret, 'sharedSecret', 'must not be empty');
    }

    final interval = codeInterval(now: now, serverTimeDiffMs: serverTimeDiffMs);
    // Avoid ByteData.setUint64 — unsupported on dart2js/web.
    final message = _uint64Be(interval);
    final digest = Hmac(sha1, sharedSecret).convert(message);
    final mac = digest.bytes;

    final offset = mac[19] & 0x0f;
    final fullCode = ((mac[offset] & 0x7f) << 24) |
        ((mac[offset + 1] & 0xff) << 16) |
        ((mac[offset + 2] & 0xff) << 8) |
        (mac[offset + 3] & 0xff);

    var value = fullCode;
    final code = StringBuffer();
    for (var i = 0; i < codeDigits; i++) {
      code.write(steamChars[value % steamChars.length]);
      value ~/= steamChars.length;
    }
    return code.toString();
  }

  /// Convenience wrapper that Base64-decodes [sharedSecretBase64] first.
  static String codeFromBase64SharedSecret({
    required String sharedSecretBase64,
    required DateTime now,
    int serverTimeDiffMs = 0,
  }) {
    final secret = base64.decode(_normalizeBase64(sharedSecretBase64));
    return codeFromSharedSecret(
      sharedSecret: secret,
      now: now,
      serverTimeDiffMs: serverTimeDiffMs,
    );
  }

  /// Steam Guard counter: floor((localMs + serverTimeDiffMs) / 30000).
  static int codeInterval({
    required DateTime now,
    int serverTimeDiffMs = 0,
  }) {
    final adjustedMs = now.millisecondsSinceEpoch + serverTimeDiffMs;
    return adjustedMs ~/ _periodMs;
  }

  /// Seconds remaining in the current 30s window (1–30 inclusive).
  static int secondsRemaining(
    DateTime now, {
    int serverTimeDiffMs = 0,
  }) {
    final adjustedMs = now.millisecondsSinceEpoch + serverTimeDiffMs;
    final elapsedInWindow = (adjustedMs ~/ 1000) % periodSeconds;
    final remaining = periodSeconds - elapsedInWindow;
    return remaining == 0 ? periodSeconds : remaining;
  }

  static String _normalizeBase64(String value) {
    final trimmed = value.trim();
    final remainder = trimmed.length % 4;
    if (remainder == 0) return trimmed;
    return trimmed.padRight(trimmed.length + (4 - remainder), '=');
  }

  /// Big-endian 8-byte encoding of a non-negative 64-bit counter.
  ///
  /// Implemented without [ByteData.setUint64] so it works on web (dart2js).
  static Uint8List _uint64Be(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'must be non-negative');
    }
    final out = Uint8List(8);
    // Split into high/low 32-bit halves; fine for all practical Unix counters.
    final high = (value ~/ 0x100000000) & 0xffffffff;
    final low = value & 0xffffffff;
    out[0] = (high >> 24) & 0xff;
    out[1] = (high >> 16) & 0xff;
    out[2] = (high >> 8) & 0xff;
    out[3] = high & 0xff;
    out[4] = (low >> 24) & 0xff;
    out[5] = (low >> 16) & 0xff;
    out[6] = (low >> 8) & 0xff;
    out[7] = low & 0xff;
    return out;
  }
}
