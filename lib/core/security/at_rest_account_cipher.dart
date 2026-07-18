import 'dart:typed_data';

import 'account_cipher.dart';
import 'aes_gcm_account_cipher.dart';
import 'plain_account_cipher.dart';

/// At-rest protection: AES-GCM when enabled, plain JSON when not.
///
/// Product default is **on** ([encryptAtRest] == true). Decrypt auto-detects
/// format so accounts written under either mode can still be opened after a
/// toggle. A settings switch can turn encryption off for advanced users.
class AtRestAccountCipher implements AccountCipher {
  AtRestAccountCipher({
    AccountCipher? plain,
    required AccountCipher encrypted,
    this.encryptAtRest = true,
  })  : _plain = plain ?? const PlainAccountCipher(),
        _encrypted = encrypted;

  final AccountCipher _plain;
  final AccountCipher _encrypted;

  /// When true, new writes use AES-GCM. When false, new writes are plain JSON.
  bool encryptAtRest;

  bool get isEncrypting => encryptAtRest;

  @override
  Future<Uint8List> encrypt(
    List<int> plaintext, {
    required String accountId,
  }) {
    return encryptAtRest
        ? _encrypted.encrypt(plaintext, accountId: accountId)
        : _plain.encrypt(plaintext, accountId: accountId);
  }

  @override
  Future<Uint8List> decrypt(
    List<int> ciphertext, {
    required String accountId,
  }) {
    if (_looksLikeAesGcm(ciphertext)) {
      return _encrypted.decrypt(ciphertext, accountId: accountId);
    }
    return _plain.decrypt(ciphertext, accountId: accountId);
  }

  /// AES-GCM wire format starts with version byte `1` and is longer than a
  /// header; plain payloads are UTF-8 JSON starting with `{`.
  static bool _looksLikeAesGcm(List<int> data) {
    if (data.length < AesGcmAccountCipher.headerLength) return false;
    if (data[0] != AesGcmAccountCipher.formatVersion) return false;
    return true;
  }
}
