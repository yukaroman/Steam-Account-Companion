import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'account_cipher.dart';
import 'account_integrity_exception.dart';
import 'master_key_service.dart';

/// AES-256-GCM account payload cipher with account-bound AAD.
///
/// Wire format:
/// `version (1 byte) | nonce (12) | mac (16) | ciphertext`
///
/// AAD (not stored, recomputed on decrypt):
/// `sac-v1|<accountId>` as UTF-8.
class AesGcmAccountCipher implements AccountCipher {
  AesGcmAccountCipher({
    required MasterKeyService masterKeyService,
    AesGcm? algorithm,
  })  : _masterKeyService = masterKeyService,
        _algorithm = algorithm ?? AesGcm.with256bits();

  static const int formatVersion = 1;
  static const int nonceLength = 12;
  static const int macLength = 16;
  static const int headerLength = 1 + nonceLength + macLength;
  static const aadPrefix = 'sac-v1|';

  final MasterKeyService _masterKeyService;
  final AesGcm _algorithm;

  /// Builds the authenticated associated data for [accountId].
  static List<int> aadFor(String accountId) {
    if (accountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    return utf8.encode('$aadPrefix$accountId');
  }

  @override
  Future<Uint8List> encrypt(
    List<int> plaintext, {
    required String accountId,
  }) async {
    final keyBytes = await _masterKeyService.getOrCreateMasterKey();
    final secretKey = await _algorithm.newSecretKeyFromBytes(keyBytes);
    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      aad: aadFor(accountId),
    );

    if (secretBox.nonce.length != nonceLength) {
      throw StateError(
          'Unexpected AES-GCM nonce length ${secretBox.nonce.length}');
    }
    if (secretBox.mac.bytes.length != macLength) {
      throw StateError(
          'Unexpected AES-GCM MAC length ${secretBox.mac.bytes.length}');
    }

    final out = Uint8List(headerLength + secretBox.cipherText.length);
    out[0] = formatVersion;
    out.setRange(1, 1 + nonceLength, secretBox.nonce);
    out.setRange(1 + nonceLength, headerLength, secretBox.mac.bytes);
    out.setRange(headerLength, out.length, secretBox.cipherText);
    return out;
  }

  @override
  Future<Uint8List> decrypt(
    List<int> ciphertext, {
    required String accountId,
  }) async {
    if (ciphertext.length < headerLength) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'ciphertext too short',
      );
    }
    if (ciphertext[0] != formatVersion) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'unsupported cipher format version',
      );
    }

    final nonce = ciphertext.sublist(1, 1 + nonceLength);
    final macBytes = ciphertext.sublist(1 + nonceLength, headerLength);
    final body = ciphertext.sublist(headerLength);

    final keyBytes = await _masterKeyService.getOrCreateMasterKey();
    final secretKey = await _algorithm.newSecretKeyFromBytes(keyBytes);
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(body, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
        aad: aadFor(accountId),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'authentication failed',
      );
    }
  }
}
