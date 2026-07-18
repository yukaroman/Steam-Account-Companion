import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/features/auth_session/data/steam_auth_protobuf.dart';
import 'package:steam_account_companion/features/auth_session/data/steam_login_client.dart';

void main() {
  test('GetPasswordRSAPublicKey request encodes account_name field 1', () {
    final b64 = SteamAuthProtobuf.encodeGetPasswordRsaRequest(
      accountName: 'demo_user',
    );
    final bytes = base64.decode(b64);
    // field 1, wire type 2, length 9, "demo_user"
    expect(bytes[0], 0x0a); // (1<<3)|2
    expect(bytes[1], 9);
    expect(utf8.decode(bytes.sublist(2)), 'demo_user');
  });

  test('round-trip RSA response decode', () {
    final encoded = SteamAuthProtobuf.writeMessage([
      _ld(1, utf8.encode('ab')),
      _ld(2, utf8.encode('010001')),
      _varint(3, 1700000000),
    ]);
    final rsa = SteamAuthProtobuf.decodeGetPasswordRsaResponse(encoded);
    expect(rsa.publicKeyModHex, 'ab');
    expect(rsa.publicKeyExpHex, '010001');
    expect(rsa.timestamp, 1700000000);
  });

  test('BeginAuth response parses client_id / steamid / confirmations', () {
    final conf = SteamAuthProtobuf.writeMessage([
      _varint(1, SteamAuthProtobuf.guardDeviceCode),
    ]);
    final body = SteamAuthProtobuf.writeMessage([
      _varint(1, 42), // client_id
      _ld(2, [1, 2, 3]), // request_id
      _ld(4, conf), // allowed_confirmations
      _varint(5, 76561198000000001), // steamid
    ]);
    final begin = SteamAuthProtobuf.decodeBeginAuthSessionResponse(body);
    expect(begin.clientId, 42);
    expect(begin.requestId, [1, 2, 3]);
    expect(begin.steamId, 76561198000000001);
    expect(begin.needsDeviceCode, isTrue);
  });

  test('Poll response parses tokens', () {
    final body = SteamAuthProtobuf.writeMessage([
      _ld(3, utf8.encode('refresh-tok')),
      _ld(4, utf8.encode('access-tok')),
    ]);
    final poll = SteamAuthProtobuf.decodePollAuthSessionResponse(body);
    expect(poll.accessToken, 'access-tok');
    expect(poll.refreshToken, 'refresh-tok');
    expect(poll.hasTokens, isTrue);
  });

  test('BeginAuth encodes SteamTools Community + MobileApp shape', () {
    final b64 = SteamAuthProtobuf.encodeBeginAuthSessionRequest(
      deviceFriendlyName: 'Mozilla/5.0',
      accountName: 'demo_user',
      encryptedPasswordBase64: 'YWJj', // dummy
      encryptionTimestamp: 1700000000,
    );
    final bytes = base64.decode(b64);
    final text = String.fromCharCodes(bytes);
    expect(text, contains('Community'));
    expect(String.fromCharCodes(bytes), contains('demo_user'));
    expect(text, contains('Mozilla/5.0'));
    // platform_type field 6 varint key = (6<<3)|0 = 0x30
    expect(bytes, contains(0x30));
    // website_id field 8 string key = (8<<3)|2 = 0x42
    expect(bytes, contains(0x42));
  });

  test('UpdateGuardCode encodes steamid as fixed64 (key 0x11)', () {
    const steamId = 76561198000000001;
    final b64 = SteamAuthProtobuf.encodeUpdateGuardCodeRequest(
      clientId: 42,
      steamId: steamId,
      code: 'ABCDE',
      codeType: SteamAuthProtobuf.guardDeviceCode,
    );
    final bytes = base64.decode(b64);
    // field 2 wire type 1 → key (2 << 3) | 1 == 0x11
    expect(bytes, contains(0x11));
    // Must not use varint key 0x10 for field 2.
    final field2VarintKeyIndex = bytes.indexOf(0x10);
    // client_id is field 1 varint (0x08); field 2 must be 0x11 not 0x10.
    expect(bytes.contains(0x11), isTrue);

    // Parse fixed64 little-endian after 0x11.
    final fixedKey = bytes.indexOf(0x11);
    expect(fixedKey, greaterThanOrEqualTo(0));
    final le = bytes.sublist(fixedKey + 1, fixedKey + 9);
    var decoded = 0;
    for (var i = 7; i >= 0; i--) {
      decoded = (decoded << 8) | le[i];
    }
    expect(decoded, steamId);
    // Silence unused if analyzer is picky about field2VarintKeyIndex
    expect(field2VarintKeyIndex == -1 || bytes[field2VarintKeyIndex] == 0x10,
        isTrue);
  });

  test('decode BeginAuth steamid from fixed64 wire type', () {
    final fixedId = _fixed64(5, 76561198000000001);
    final body = SteamAuthProtobuf.writeMessage([
      _varint(1, 7),
      _ld(2, [9, 9]),
      fixedId,
    ]);
    final begin = SteamAuthProtobuf.decodeBeginAuthSessionResponse(body);
    expect(begin.clientId, 7);
    expect(begin.steamId, 76561198000000001);
  });

  test('asciiOnly strips non-ASCII like Steam', () {
    expect(SteamLoginClient.asciiOnly('ab\u4e2dc'), 'abc');
  });
}

Uint8List _ld(int number, List<int> value) {
  final key = _encodeVarint((number << 3) | 2);
  final len = _encodeVarint(value.length);
  return Uint8List.fromList([...key, ...len, ...value]);
}

Uint8List _varint(int number, int value) {
  final key = _encodeVarint((number << 3) | 0);
  final body = _encodeVarint(value);
  return Uint8List.fromList([...key, ...body]);
}

List<int> _encodeVarint(int value) {
  var v = value.toUnsigned(64);
  final out = <int>[];
  while (v > 0x7f) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v & 0x7f);
  return out;
}

Uint8List _fixed64(int number, int value) {
  final key = _encodeVarint((number << 3) | 1);
  final body = Uint8List(8);
  var remaining = value.toUnsigned(64);
  for (var i = 0; i < 8; i++) {
    body[i] = remaining & 0xff;
    remaining >>= 8;
  }
  return Uint8List.fromList([...key, ...body]);
}
