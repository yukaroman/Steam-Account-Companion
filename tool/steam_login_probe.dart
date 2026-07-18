import 'package:http/http.dart' as http;
import 'package:steam_account_companion/features/auth_session/data/steam_auth_protobuf.dart';
import 'package:steam_account_companion/features/auth_session/data/steam_login_client.dart';

/// Local diagnostic: dart run tool/steam_login_probe.dart
void main() async {
  final encoded = SteamAuthProtobuf.encodeGetPasswordRsaRequest(
    accountName: 'testuser_not_real_xyz',
  );
  final uri = Uri.parse(
    'https://api.steampowered.com/IAuthenticationService/GetPasswordRSAPublicKey/v1/',
  ).replace(queryParameters: {
    'input_protobuf_encoded': encoded,
    'origin': 'SteamMobile',
  });
  final r = await http.get(uri, headers: {
    'User-Agent': 'okhttp/4.9.2',
    'Accept': 'application/json, text/plain, */*',
    'Cookie': 'mobileClient=android; mobileClientVersion=777777 3.10.3',
  });
  // ignore: avoid_print
  print('status=${r.statusCode} eresult=${r.headers['x-eresult']} '
      'ct=${r.headers['content-type']} len=${r.bodyBytes.length}');
  // ignore: avoid_print
  print(
    'hex=${r.bodyBytes.take(80).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
  );
  try {
    final rsa = SteamAuthProtobuf.decodeGetPasswordRsaResponse(r.bodyBytes);
    // ignore: avoid_print
    print(
      'modLen=${rsa.publicKeyModHex.length} exp=${rsa.publicKeyExpHex} ts=${rsa.timestamp}',
    );
    final enc = SteamLoginClient.encryptPasswordRsa(
      password: 'dummy-pass',
      modHex: rsa.publicKeyModHex,
      expHex: rsa.publicKeyExpHex,
    );
    // ignore: avoid_print
    print('enc ok len=${enc.length}');

    final beginEnc = SteamAuthProtobuf.encodeBeginAuthSessionRequest(
      deviceFriendlyName: 'Steam Account Companion',
      accountName: 'testuser_not_real_xyz',
      encryptedPasswordBase64: enc,
      encryptionTimestamp: rsa.timestamp,
    );
    final begin = await http.post(
      Uri.parse(
        'https://api.steampowered.com/IAuthenticationService/BeginAuthSessionViaCredentials/v1/',
      ),
      headers: {
        'User-Agent': 'okhttp/4.9.2',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        'Cookie': 'mobileClient=android; mobileClientVersion=777777 3.10.3',
      },
      body: {'input_protobuf_encoded': beginEnc},
    );
    // ignore: avoid_print
    print(
      'begin status=${begin.statusCode} eresult=${begin.headers['x-eresult']} '
      'len=${begin.bodyBytes.length}',
    );
    final parsed =
        SteamAuthProtobuf.decodeBeginAuthSessionResponse(begin.bodyBytes);
    // ignore: avoid_print
    print(
      'clientId=${parsed.clientId} steamId=${parsed.steamId} '
      'confs=${parsed.allowedConfirmations.map((c) => c.confirmationType).toList()}',
    );
  } catch (e, st) {
    // ignore: avoid_print
    print('ERR $e\n$st');
  }
}
