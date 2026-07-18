import 'dart:convert';
import 'dart:typed_data';

/// Minimal protobuf wire helpers for Steam Auth V2 messages.
///
/// Field numbers match SteamClient / steammessages_auth.steamclient.proto.
class SteamAuthProtobuf {
  SteamAuthProtobuf._();

  // EAuthSessionGuardType
  static const int guardUnknown = 0;
  static const int guardEmailCode = 2;
  static const int guardDeviceCode = 3;
  static const int guardDeviceConfirmation = 4;
  static const int guardEmailConfirmation = 5;
  static const int guardMachineToken = 6;

  // EAuthTokenPlatformType
  static const int platformMobileApp = 3;

  /// DoctorMcKay / official mobile: `website_id = "Mobile"`.
  static const String websiteIdMobile = 'Mobile';

  /// EOSType.AndroidUnknown from Steam enums (signed int32).
  static const int osTypeAndroidUnknown = -500;

  /// Observed mobile gaming_device_type (node-steam-session MobileApp).
  static const int gamingDeviceTypeMobile = 528;

  // ESessionPersistence
  static const int persistencePersistent = 1;

  static String encodeGetPasswordRsaRequest({required String accountName}) {
    return base64.encode(writeMessage([
      _stringField(1, accountName),
    ]));
  }

  static RsaPublicKeyResponse decodeGetPasswordRsaResponse(List<int> bytes) {
    String? mod;
    String? exp;
    int? timestamp;
    for (final f in _readFields(bytes)) {
      switch (f.number) {
        case 1:
          mod = utf8.decode(f.bytes);
        case 2:
          exp = utf8.decode(f.bytes);
        case 3:
          timestamp = _asInt(f);
      }
    }
    if (mod == null || exp == null || timestamp == null) {
      throw const FormatException('RSA public key response incomplete');
    }
    return RsaPublicKeyResponse(
      publicKeyModHex: mod,
      publicKeyExpHex: exp,
      timestamp: timestamp,
    );
  }

  static String encodeBeginAuthSessionRequest({
    required String deviceFriendlyName,
    required String accountName,
    required String encryptedPasswordBase64,
    required int encryptionTimestamp,
    bool rememberLogin = true,
    int platformType = platformMobileApp,
    int persistence = persistencePersistent,

    /// SteamTools uses `Community` with MobileApp platform and works in prod.
    /// DoctorMcKay MobileApp uses `Mobile` + nested device_details.
    String websiteId = 'Community',
    int osType = osTypeAndroidUnknown,
    int gamingDeviceType = gamingDeviceTypeMobile,
    bool includeDeviceDetails = false,
  }) {
    // SteamTools / BeyondDimension SteamClient (working reference):
    //   device_friendly_name, account_name, encrypted_password,
    //   encryption_timestamp, remember_login, platform_type=MobileApp,
    //   persistence, website_id="Community"
    // No nested device_details.
    final parts = <Uint8List>[
      _stringField(1, deviceFriendlyName),
      _stringField(2, accountName),
      _stringField(3, encryptedPasswordBase64),
      _varintField(4, encryptionTimestamp),
      _boolField(5, rememberLogin),
      _varintField(6, platformType),
      _varintField(7, persistence),
      _stringField(8, websiteId),
    ];
    if (includeDeviceDetails) {
      final deviceDetails = writeMessage([
        _stringField(1, deviceFriendlyName),
        _varintField(2, platformType),
        _varintField(3, osType),
        _varintField(4, gamingDeviceType),
      ]);
      parts.add(_bytesField(9, deviceDetails));
    }
    return base64.encode(writeMessage(parts));
  }

  static BeginAuthSessionResponse decodeBeginAuthSessionResponse(
    List<int> bytes,
  ) {
    int? clientId;
    Uint8List? requestId;
    final confirmations = <AllowedConfirmation>[];
    int? steamId;
    for (final f in _readFields(bytes)) {
      switch (f.number) {
        case 1:
          clientId = _asInt(f);
        case 2:
          requestId = Uint8List.fromList(f.bytes);
        case 4:
          confirmations.add(_decodeAllowedConfirmation(f.bytes));
        case 5:
          steamId = _asInt(f);
      }
    }
    return BeginAuthSessionResponse(
      clientId: clientId ?? 0,
      requestId: requestId ?? Uint8List(0),
      steamId: steamId ?? 0,
      allowedConfirmations: confirmations,
    );
  }

  static String encodeUpdateGuardCodeRequest({
    required int clientId,
    required int steamId,
    required String code,
    required int codeType,
  }) {
    return base64.encode(writeMessage([
      _varintField(1, clientId),
      // steamid is protobuf fixed64 (wire type 1), not varint.
      _fixed64Field(2, steamId),
      _stringField(3, code),
      _varintField(4, codeType),
    ]));
  }

  static String encodePollAuthSessionRequest({
    required int clientId,
    required List<int> requestId,
  }) {
    return base64.encode(writeMessage([
      _varintField(1, clientId),
      _bytesField(2, requestId),
    ]));
  }

  static PollAuthSessionResponse decodePollAuthSessionResponse(
    List<int> bytes,
  ) {
    String? refreshToken;
    String? accessToken;
    for (final f in _readFields(bytes)) {
      switch (f.number) {
        case 3:
          refreshToken = utf8.decode(f.bytes);
        case 4:
          accessToken = utf8.decode(f.bytes);
      }
    }
    return PollAuthSessionResponse(
      accessToken: accessToken ?? '',
      refreshToken: refreshToken ?? '',
    );
  }

  static AllowedConfirmation _decodeAllowedConfirmation(List<int> bytes) {
    var type = guardUnknown;
    String? message;
    for (final f in _readFields(bytes)) {
      switch (f.number) {
        case 1:
          type = _asInt(f);
        case 2:
          message = utf8.decode(f.bytes);
      }
    }
    return AllowedConfirmation(
        confirmationType: type, associatedMessage: message);
  }

  // --- wire helpers ---

  static Uint8List writeMessage(List<Uint8List> parts) {
    final length = parts.fold<int>(0, (sum, p) => sum + p.length);
    final out = Uint8List(length);
    var offset = 0;
    for (final p in parts) {
      out.setRange(offset, offset + p.length, p);
      offset += p.length;
    }
    return out;
  }

  static Uint8List _stringField(int number, String value) {
    return _lengthDelimitedField(number, utf8.encode(value));
  }

  static Uint8List _bytesField(int number, List<int> value) {
    return _lengthDelimitedField(number, value);
  }

  static Uint8List _lengthDelimitedField(int number, List<int> value) {
    final key = _encodeVarint((number << 3) | 2);
    final len = _encodeVarint(value.length);
    return Uint8List.fromList([...key, ...len, ...value]);
  }

  static Uint8List _varintField(int number, int value) {
    final key = _encodeVarint((number << 3) | 0);
    final body = _encodeVarint(value);
    return Uint8List.fromList([...key, ...body]);
  }

  /// Protobuf fixed64: key wire type 1, then 8 little-endian bytes.
  static Uint8List _fixed64Field(int number, int value) {
    final key = _encodeVarint((number << 3) | 1);
    return Uint8List.fromList([...key, ..._fixed64Bytes(value)]);
  }

  /// Little-endian unsigned 64-bit layout for [value].
  static Uint8List _fixed64Bytes(int value) {
    final out = Uint8List(8);
    var remaining = value.toUnsigned(64);
    for (var index = 0; index < 8; index++) {
      out[index] = remaining & 0xff;
      remaining >>= 8;
    }
    return out;
  }

  static Uint8List _boolField(int number, bool value) {
    return _varintField(number, value ? 1 : 0);
  }

  static List<int> _encodeVarint(int value) {
    // Support full 64-bit range for steamids / client ids.
    var v = value.toUnsigned(64);
    final out = <int>[];
    while (v > 0x7f) {
      out.add((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.add(v & 0x7f);
    return out;
  }

  static int _asInt(_Field f) {
    if (f.wireType == 0) return f.varint;
    if (f.wireType == 1) return f.varint;
    if (f.wireType == 2 && f.bytes.isEmpty) return 0;
    // Length-delimited varint is unusual; fall back to first-byte parse.
    return f.varint;
  }

  static List<_Field> _readFields(List<int> bytes) {
    final fields = <_Field>[];
    var i = 0;
    while (i < bytes.length) {
      final key = _readVarint(bytes, i);
      i = key.next;
      final number = key.value >> 3;
      final wireType = key.value & 0x7;
      if (wireType == 0) {
        final body = _readVarint(bytes, i);
        i = body.next;
        fields.add(_Field(number, wireType, varint: body.value));
      } else if (wireType == 2) {
        final len = _readVarint(bytes, i);
        i = len.next;
        final end = i + len.value;
        if (end > bytes.length) {
          throw const FormatException('protobuf length out of range');
        }
        fields.add(
          _Field(
            number,
            wireType,
            bytes: bytes.sublist(i, end),
          ),
        );
        i = end;
      } else if (wireType == 5) {
        // 32-bit — skip
        i += 4;
      } else if (wireType == 1) {
        if (i + 8 > bytes.length) {
          throw const FormatException('truncated fixed64');
        }
        final fixed = bytes.sublist(i, i + 8);
        i += 8;
        fields.add(
          _Field(number, wireType, varint: _readFixed64LittleEndian(fixed)),
        );
      } else {
        throw FormatException('unsupported protobuf wire type $wireType');
      }
    }
    return fields;
  }

  static int _readFixed64LittleEndian(List<int> bytes) {
    var value = 0;
    for (var index = 7; index >= 0; index--) {
      value = (value << 8) | (bytes[index] & 0xff);
    }
    return value;
  }

  static ({int value, int next}) _readVarint(List<int> bytes, int start) {
    var result = 0;
    var shift = 0;
    var i = start;
    while (i < bytes.length) {
      final b = bytes[i++];
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) {
        return (value: result, next: i);
      }
      shift += 7;
      if (shift > 63) {
        throw const FormatException('varint too long');
      }
    }
    throw const FormatException('truncated varint');
  }
}

class RsaPublicKeyResponse {
  const RsaPublicKeyResponse({
    required this.publicKeyModHex,
    required this.publicKeyExpHex,
    required this.timestamp,
  });

  final String publicKeyModHex;
  final String publicKeyExpHex;
  final int timestamp;
}

class AllowedConfirmation {
  const AllowedConfirmation({
    required this.confirmationType,
    this.associatedMessage,
  });

  final int confirmationType;
  final String? associatedMessage;
}

class BeginAuthSessionResponse {
  const BeginAuthSessionResponse({
    required this.clientId,
    required this.requestId,
    required this.steamId,
    required this.allowedConfirmations,
  });

  final int clientId;
  final Uint8List requestId;
  final int steamId;
  final List<AllowedConfirmation> allowedConfirmations;

  bool get needsDeviceCode => allowedConfirmations.any(
        (c) => c.confirmationType == SteamAuthProtobuf.guardDeviceCode,
      );

  bool get needsEmailCode => allowedConfirmations.any(
        (c) => c.confirmationType == SteamAuthProtobuf.guardEmailCode,
      );

  bool get needsDeviceConfirmation => allowedConfirmations.any(
        (c) => c.confirmationType == SteamAuthProtobuf.guardDeviceConfirmation,
      );

  bool get needsEmailConfirmation => allowedConfirmations.any(
        (c) => c.confirmationType == SteamAuthProtobuf.guardEmailConfirmation,
      );

  String? get emailHint {
    for (final c in allowedConfirmations) {
      if (c.confirmationType == SteamAuthProtobuf.guardEmailCode) {
        return c.associatedMessage;
      }
    }
    return null;
  }
}

class PollAuthSessionResponse {
  const PollAuthSessionResponse({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  bool get hasTokens =>
      accessToken.trim().isNotEmpty && refreshToken.trim().isNotEmpty;
}

class _Field {
  _Field(
    this.number,
    this.wireType, {
    this.bytes = const [],
    this.varint = 0,
  });

  final int number;
  final int wireType;
  final List<int> bytes;
  final int varint;
}
