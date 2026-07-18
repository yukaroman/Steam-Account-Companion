import 'dart:convert';
import 'dart:typed_data';

import '../../features/accounts/models/steam_account_payload.dart';

/// Encodes/decodes [SteamAccountPayload] to UTF-8 JSON bytes.
///
/// Does not encrypt. Pair with [AccountCipher] before persistence.
abstract final class AccountPayloadCodec {
  static Uint8List encode(SteamAccountPayload payload) {
    final json = jsonEncode(payload.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  static SteamAccountPayload decode(List<int> bytes) {
    final jsonText = utf8.decode(bytes);
    final map = jsonDecode(jsonText);
    if (map is! Map) {
      throw const FormatException('Account payload JSON must be an object');
    }
    return SteamAccountPayload.fromJson(Map<String, Object?>.from(map));
  }
}
