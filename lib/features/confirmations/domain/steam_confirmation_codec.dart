import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Pure helpers for Steam mobile confirmation request keys.
///
/// Matches Steam Desktop Authenticator / mobile Steam Guard:
/// HMAC-SHA1(identity_secret, big-endian-time-seconds ‖ tag) → Base64.
abstract final class SteamConfirmationCodec {
  /// Generates the `k` query parameter for mobileconf endpoints.
  static String confirmationKey({
    required List<int> identitySecret,
    required int timeSeconds,
    required String tag,
  }) {
    if (identitySecret.isEmpty) {
      throw ArgumentError.value(
        identitySecret,
        'identitySecret',
        'must not be empty',
      );
    }
    if (timeSeconds < 0) {
      throw ArgumentError.value(timeSeconds, 'timeSeconds', 'must be >= 0');
    }
    final tagBytes = utf8.encode(tag);
    final buffer = Uint8List(8 + tagBytes.length);
    var t = timeSeconds;
    for (var i = 7; i >= 0; i--) {
      buffer[i] = t & 0xff;
      t >>= 8;
    }
    buffer.setRange(8, 8 + tagBytes.length, tagBytes);
    final mac = Hmac(sha1, identitySecret).convert(buffer);
    return base64.encode(mac.bytes);
  }

  /// Convenience for Base64-encoded [identitySecretBase64].
  static String confirmationKeyFromBase64({
    required String identitySecretBase64,
    required int timeSeconds,
    required String tag,
  }) {
    final secret = base64.decode(_normalizeBase64(identitySecretBase64));
    return confirmationKey(
      identitySecret: secret,
      timeSeconds: timeSeconds,
      tag: tag,
    );
  }

  static String _normalizeBase64(String value) {
    final trimmed = value.trim();
    final remainder = trimmed.length % 4;
    if (remainder == 0) return trimmed;
    return trimmed.padRight(trimmed.length + (4 - remainder), '=');
  }
}
