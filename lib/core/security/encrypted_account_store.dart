/// Encrypted persistence boundary for account payloads.
///
/// Implementations must never log [encryptedPayload] or return decrypted
/// secrets to presentation-layer code. Callers encrypt with [AccountCipher]
/// before [save].
abstract interface class EncryptedAccountStore {
  Future<void> save({
    required String accountId,
    required List<int> encryptedPayload,
  });

  Future<List<int>?> read(String accountId);

  Future<void> delete(String accountId);

  /// Account ids that currently have a stored ciphertext blob.
  Future<List<String>> listAccountIds();
}
