enum ConfirmationKind { login, trade, market, other }

enum ConfirmationRisk { low, medium, high }

/// A pending Steam mobile confirmation for presentation + API actions.
class SteamConfirmation {
  const SteamConfirmation({
    required this.id,
    required this.nonce,
    required this.accountId,
    required this.accountName,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    required this.risk,
    this.creationTime,
    this.iconUrl,
  });

  /// Steam confirmation id (`cid`).
  final String id;

  /// Steam confirmation nonce / creator key (`ck`).
  final String nonce;

  /// Local account id in [AccountsRepository].
  final String accountId;

  final String accountName;
  final ConfirmationKind kind;
  final String title;
  final String subtitle;
  final String timeLabel;
  final ConfirmationRisk risk;
  final int? creationTime;
  final String? iconUrl;
}

/// Failure from listing or acting on confirmations.
class ConfirmationsException implements Exception {
  const ConfirmationsException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ConfirmationsException($code): $message';
}
