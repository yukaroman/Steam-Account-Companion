/// Outcome of an import attempt. Safe for UI (no secrets).
class ImportResult {
  const ImportResult({
    required this.successCount,
    required this.failures,
    this.importedAccountIds = const [],
    this.importedDisplayNames = const [],
  });

  final int successCount;
  final List<ImportFailure> failures;
  final List<String> importedAccountIds;

  /// UI-facing names (Steam username / account_name), parallel to [importedAccountIds].
  final List<String> importedDisplayNames;

  bool get hasSuccess => successCount > 0;
  bool get hasFailures => failures.isNotEmpty;
}

class ImportFailure {
  const ImportFailure({
    required this.code,
    required this.message,
    this.sourceLabel,
  });

  final String code;
  final String message;

  /// File name or "pasted JSON" — never file body.
  final String? sourceLabel;
}
