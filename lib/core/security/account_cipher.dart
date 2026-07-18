import 'dart:typed_data';

/// Transforms account payload bytes before persistence.
///
/// Production options:
/// - [AesGcmAccountCipher] — AES-256-GCM (product default path)
/// - [PlainAccountCipher] — no at-rest encryption (advanced opt-out)
/// - [AtRestAccountCipher] — switchable wrapper (default on)
///
/// [accountId] is bound into authenticated encryption context (AAD) so a
/// ciphertext cannot be moved under another storage key.
abstract interface class AccountCipher {
  Future<Uint8List> encrypt(
    List<int> plaintext, {
    required String accountId,
  });

  Future<Uint8List> decrypt(
    List<int> ciphertext, {
    required String accountId,
  });
}
