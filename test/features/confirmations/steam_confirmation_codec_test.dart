import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/features/confirmations/domain/steam_confirmation_codec.dart';

void main() {
  // identity_secret = base64("identity-secret-1")
  const identityB64 = 'aWRlbnRpdHktc2VjcmV0LTE=';
  const time = 1700000000;

  test('confirmation keys match SteamTools/WinAuth tags', () {
    expect(
      SteamConfirmationCodec.confirmationKeyFromBase64(
        identitySecretBase64: identityB64,
        timeSeconds: time,
        tag: 'list',
      ),
      'LmdS0uGV3mbGJlFHNfIjhYTa01Q=',
    );
    expect(
      SteamConfirmationCodec.confirmationKeyFromBase64(
        identitySecretBase64: identityB64,
        timeSeconds: time,
        tag: 'accept',
      ),
      'qB+lvtFax3W5mOZUxwsqkTTxcfA=',
    );
    expect(
      SteamConfirmationCodec.confirmationKeyFromBase64(
        identitySecretBase64: identityB64,
        timeSeconds: time,
        tag: 'reject',
      ),
      'b7Awp37sd1pM1xR7uQv4xV4nZ/w=',
    );
  });

  test('raw secret path matches base64 path', () {
    final raw = base64.decode(identityB64);
    final fromRaw = SteamConfirmationCodec.confirmationKey(
      identitySecret: raw,
      timeSeconds: time,
      tag: 'list',
    );
    final fromB64 = SteamConfirmationCodec.confirmationKeyFromBase64(
      identitySecretBase64: identityB64,
      timeSeconds: time,
      tag: 'list',
    );
    expect(fromRaw, fromB64);
  });
}
