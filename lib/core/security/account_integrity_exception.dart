/// Thrown when stored account ciphertext fails integrity / binding checks.
///
/// Message must stay free of secrets, codes, and raw payload contents.
class AccountIntegrityException implements Exception {
  const AccountIntegrityException(this.code, [this.message]);

  /// Stable machine-readable code for tests and UI mapping.
  final String code;

  /// Optional sanitized human-readable detail.
  final String? message;

  static const swappedOrTampered = 'account_blob_integrity_failed';
  static const payloadIdMismatch = 'payload_account_id_mismatch';

  @override
  String toString() {
    if (message == null || message!.isEmpty) {
      return 'AccountIntegrityException($code)';
    }
    return 'AccountIntegrityException($code): $message';
  }
}
