import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../accounts/domain/accounts_repository.dart';
import '../../accounts/models/steam_account_private_meta.dart';
import '../../accounts/models/steam_account_profile.dart';
import '../../accounts/models/steam_account_secrets.dart';
import '../data/mafile_models.dart';
import '../data/mafile_parser.dart';
import 'import_result.dart';

/// Imports parsed maFile data into [AccountsRepository].
///
/// Presentation must only receive [ImportResult] / profiles — never [MaFileData].
class AccountImporter {
  AccountImporter({
    required AccountsRepository repository,
    MaFileParser? parser,
  })  : _repository = repository,
        _parser = parser ?? const MaFileParser();

  final AccountsRepository _repository;
  final MaFileParser _parser;

  /// Palette for avatar colors (ARGB).
  static const _avatarPalette = <int>[
    0xFF6B8CFF,
    0xFF9B87FF,
    0xFF3DDC97,
    0xFF5CE1FF,
    0xFFFFC857,
    0xFFFF6B81,
  ];

  Future<ImportResult> importJsonString(
    String source, {
    String? sourceLabel,
  }) async {
    try {
      final accounts = _parser.parseAll(source);
      final ids = <String>[];
      final names = <String>[];
      for (final data in accounts) {
        final upserted = await _upsertMaFile(data);
        ids.add(upserted.accountId);
        names.add(upserted.displayName);
      }
      return ImportResult(
        successCount: ids.length,
        failures: const [],
        importedAccountIds: ids,
        importedDisplayNames: names,
      );
    } on MaFileParseException catch (error) {
      return ImportResult(
        successCount: 0,
        failures: [
          ImportFailure(
            code: error.code,
            message: error.message,
            sourceLabel: sourceLabel,
          ),
        ],
      );
    } catch (_) {
      return ImportResult(
        successCount: 0,
        failures: [
          ImportFailure(
            code: 'import_failed',
            message: 'Could not import account',
            sourceLabel: sourceLabel,
          ),
        ],
      );
    }
  }

  Future<ImportResult> importJsonStrings(
    List<({String source, String? label})> items,
  ) async {
    var success = 0;
    final failures = <ImportFailure>[];
    final ids = <String>[];
    final names = <String>[];
    for (final item in items) {
      final result = await importJsonString(
        item.source,
        sourceLabel: item.label,
      );
      success += result.successCount;
      failures.addAll(result.failures);
      ids.addAll(result.importedAccountIds);
      names.addAll(result.importedDisplayNames);
    }
    return ImportResult(
      successCount: success,
      failures: failures,
      importedAccountIds: ids,
      importedDisplayNames: names,
    );
  }

  Future<({String accountId, String displayName})> _upsertMaFile(
    MaFileData data,
  ) async {
    final accountId = _resolveAccountId(data);
    final nickname = _resolveNickname(data);
    // Product choice: show the full Steam account name in the UI (no masking).
    final displayName = (data.accountName?.trim().isNotEmpty == true)
        ? data.accountName!.trim()
        : nickname;

    final profile = SteamAccountProfile(
      id: accountId,
      nickname: nickname,
      loginNameHint: displayName,
      initials: _initials(nickname),
      avatarColorValue: _colorFor(accountId),
    );

    final privateMeta = SteamAccountPrivateMeta(
      accountName: data.accountName,
      steamId64: data.steamId64,
      serialNumber: data.serialNumber,
      deviceId: data.deviceId,
    );

    final secrets = SteamAccountSecrets.fromBase64(
      sharedSecretBase64: data.sharedSecretBase64,
      identitySecretBase64: data.identitySecretBase64,
      revocationCode: data.revocationCode,
      steamPassword: data.steamPassword,
      sessionId: data.sessionId,
      steamLoginSecure: data.steamLoginSecure,
      accessToken: data.accessToken,
      refreshToken: data.refreshToken,
    );

    await _repository.upsert(
      profile: profile,
      privateMeta: privateMeta,
      secrets: secrets,
    );
    return (accountId: accountId, displayName: displayName);
  }

  String _resolveAccountId(MaFileData data) {
    final steamId = data.steamId64?.trim();
    if (steamId != null && steamId.isNotEmpty) {
      return 'steam:$steamId';
    }
    final serial = data.serialNumber?.trim();
    if (serial != null && serial.isNotEmpty) {
      return 'serial:$serial';
    }
    final name = data.accountName?.trim();
    if (name != null && name.isNotEmpty) {
      return 'name:${name.toLowerCase()}';
    }
    // Stable id from shared_secret — never random `import:uuid` (that hid names).
    return 'guard:${_shortSecretId(data.sharedSecretBase64)}';
  }

  String _resolveNickname(MaFileData data) {
    final name = data.accountName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final serial = data.serialNumber?.trim();
    if (serial != null && serial.length >= 4) {
      return 'Guard ${serial.substring(serial.length - 4)}';
    }
    return '未命名账号';
  }

  static String _shortSecretId(String sharedSecretBase64) {
    final digest = sha256.convert(utf8.encode(sharedSecretBase64.trim()));
    return digest.toString().substring(0, 16);
  }

  static String _initials(String nickname) {
    final cleaned = nickname.trim();
    if (cleaned.isEmpty) return '?';
    // Prefer word / underscore segments: demo__login__name → DL
    final parts =
        cleaned.split(RegExp(r'[\s._-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return p.length == 1 ? p.toUpperCase() : p.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static int _colorFor(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash + unit) & 0x7fffffff;
    }
    return _avatarPalette[hash % _avatarPalette.length];
  }
}
