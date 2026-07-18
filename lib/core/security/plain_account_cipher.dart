import 'dart:typed_data';

import 'account_cipher.dart';

/// Pass-through cipher used when at-rest encryption is disabled.
///
/// Payload bytes are stored as-is (UTF-8 JSON from [AccountPayloadCodec]).
/// [accountId] is accepted for API symmetry; binding is enforced by the
/// repository after decode.
class PlainAccountCipher implements AccountCipher {
  const PlainAccountCipher();

  @override
  Future<Uint8List> encrypt(
    List<int> plaintext, {
    required String accountId,
  }) async {
    _requireAccountId(accountId);
    return Uint8List.fromList(plaintext);
  }

  @override
  Future<Uint8List> decrypt(
    List<int> ciphertext, {
    required String accountId,
  }) async {
    _requireAccountId(accountId);
    return Uint8List.fromList(ciphertext);
  }

  void _requireAccountId(String accountId) {
    if (accountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
  }
}
