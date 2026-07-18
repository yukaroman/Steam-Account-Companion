import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
// ValueNotifier lives in foundation.dart.

import '../core/network/http_steam_time_client.dart';
import '../core/network/steam_time_client.dart'
    show SteamTimeClient, SteamTimeSyncResult;
import '../core/security/account_backup_codec.dart';
import '../core/security/account_storage_paths.dart';
import '../core/security/aes_gcm_account_cipher.dart';
import '../core/security/at_rest_account_cipher.dart';
import '../core/security/biometric_service.dart';
import '../core/security/encrypted_account_store.dart';
import '../core/security/file_encrypted_account_store.dart';
import '../core/security/local_auth_biometric_service.dart';
import '../core/security/master_key_service.dart';
import '../core/security/memory_encrypted_account_store.dart';
import '../core/security/platform_secure_storage.dart';
import '../core/security/secure_storage.dart';
import '../features/accounts/data/demo_accounts_seed.dart';
import '../features/accounts/data/encrypted_accounts_repository.dart';
import '../features/accounts/domain/accounts_repository.dart';
import '../features/accounts/models/steam_account_details.dart';
import '../features/authenticator/data/local_time_provider.dart';
import '../features/authenticator/data/steam_guard_authenticator_service.dart';
import '../features/authenticator/domain/authenticator_service.dart';
import '../features/authenticator/domain/steam_time_sync_service.dart';
import '../features/authenticator/domain/time_provider.dart';
import '../features/auth_session/data/steam_login_client.dart';
import '../features/auth_session/domain/steam_login_result.dart';
import '../features/auth_session/domain/steam_session_login_service.dart';
import '../features/confirmations/data/http_steam_confirmations_client.dart';
import '../features/confirmations/data/steam_confirmations_repository.dart';
import '../features/confirmations/domain/confirmations_repository.dart';
import '../features/confirmations/domain/steam_mobile_session.dart';
import '../features/import/domain/account_importer.dart';
import '../features/import/domain/import_result.dart';

/// Lightweight composition root for account + authenticator services.
class AppServices extends ChangeNotifier {
  AppServices._({
    required this.accountsRepository,
    required SteamGuardAuthenticatorService authenticator,
    required EncryptedAccountsRepository encryptedAccounts,
    required AtRestAccountCipher atRestCipher,
    required SecureStorage secureStorage,
    required AccountImporter importer,
    required SteamTimeSyncService timeSyncService,
    required BiometricService biometricService,
    required ConfirmationsRepository confirmationsRepository,
    required HttpSteamConfirmationsClient confirmationsClient,
    required SteamSessionLoginService sessionLoginService,
  })  : _authenticator = authenticator,
        _encryptedAccounts = encryptedAccounts,
        _atRestCipher = atRestCipher,
        _secureStorage = secureStorage,
        _importer = importer,
        _timeSyncService = timeSyncService,
        _biometricService = biometricService,
        _confirmationsRepository = confirmationsRepository,
        _confirmationsClient = confirmationsClient,
        _sessionLoginService = sessionLoginService;

  static const encryptAtRestPrefKey = 'pref_encrypt_accounts_at_rest';

  /// Bumps only on account catalog changes (import / delete / restore).
  /// Confirmations UI should listen here — not every [notifyListeners] call.
  final ValueNotifier<int> accountsRevision = ValueNotifier<int>(0);

  final AccountsRepository accountsRepository;
  final EncryptedAccountsRepository _encryptedAccounts;
  final AtRestAccountCipher _atRestCipher;
  final SecureStorage _secureStorage;
  final AccountImporter _importer;
  final SteamGuardAuthenticatorService _authenticator;
  final SteamTimeSyncService _timeSyncService;
  final BiometricService _biometricService;
  final ConfirmationsRepository _confirmationsRepository;
  final HttpSteamConfirmationsClient _confirmationsClient;
  final SteamSessionLoginService _sessionLoginService;

  DateTime? _lastTimeSyncedAt;
  Object? _lastTimeSyncError;
  bool _timeSyncInProgress = false;
  Future<SteamTimeSyncResult?>? _timeSyncInFlight;
  bool _timeSyncNotifyRequested = false;

  AuthenticatorService get authenticatorService => _authenticator;

  BiometricService get biometricService => _biometricService;

  ConfirmationsRepository get confirmationsRepository =>
      _confirmationsRepository;

  SteamConfirmationsRepository? get steamConfirmationsRepository {
    final repo = _confirmationsRepository;
    return repo is SteamConfirmationsRepository ? repo : null;
  }

  /// Current Guard clock skew applied to codes (`server - local` ms).
  int get serverTimeDiffMs => _authenticator.serverTimeDiffMs;

  DateTime? get lastTimeSyncedAt => _lastTimeSyncedAt;
  Object? get lastTimeSyncError => _lastTimeSyncError;
  bool get timeSyncInProgress => _timeSyncInProgress;
  bool get hasSyncedServerTime =>
      _lastTimeSyncedAt != null && _lastTimeSyncError == null;

  /// Default is **true** — account payloads are AES-GCM wrapped at rest.
  bool get encryptAccountsAtRest => _atRestCipher.encryptAtRest;

  /// Builds app services with durable Keychain + on-disk account blobs.
  ///
  /// Production entry should keep [seedDemoAccounts] false. When true, demo
  /// accounts are only seeded if the store is confirmed empty (never after a
  /// corrupt-index recovery that still has blob files).
  static Future<AppServices> createPrototype({
    bool encryptAccountsAtRest = true,
    bool seedDemoAccounts = false,
    SecureStorage? secureStorage,
    EncryptedAccountStore? accountStore,
    SteamTimeClient? timeClient,
    TimeProvider? timeProvider,
    BiometricService? biometricService,
    bool syncServerTimeOnStart = true,
  }) async {
    // Web lacks path_provider Application Support / full Keychain semantics.
    // Fall back to in-memory storage so Chrome/web can still run the UI.
    final storage = secureStorage ??
        (kIsWeb
            ? PlatformSecureStorage.memory()
            : PlatformSecureStorage.device());
    final pref = await storage.read(encryptAtRestPrefKey);
    final encryptEnabled =
        pref == null ? encryptAccountsAtRest : pref == 'true';

    final masterKeys = MasterKeyService(secureStorage: storage);
    final aes = AesGcmAccountCipher(masterKeyService: masterKeys);
    final atRest = AtRestAccountCipher(
      encrypted: aes,
      encryptAtRest: encryptEnabled,
    );

    final EncryptedAccountStore store;
    if (accountStore != null) {
      store = accountStore;
    } else if (kIsWeb) {
      store = MemoryEncryptedAccountStore();
    } else {
      final root = await AccountStoragePaths.accountsRoot();
      final fileStore = FileEncryptedAccountStore(rootDirectory: root);
      await fileStore.ensureReady();
      store = fileStore;
    }

    final accounts = EncryptedAccountsRepository(store: store, cipher: atRest);

    if (seedDemoAccounts) {
      final existing = await accounts.listProfiles();
      if (existing.isEmpty) {
        await DemoAccountsSeed.seed(accounts);
      }
    } else {
      // Drop leftover prototype demos from older builds / prior seed flags.
      await _purgeDemoAccounts(accounts);
    }

    final clock = timeProvider ?? const LocalTimeProvider();
    final secrets = await accounts.loadSharedSecretsByAccountId();
    final authenticator = SteamGuardAuthenticatorService(
      sharedSecretsByAccountId: secrets,
      timeProvider: clock,
    );
    final importer = AccountImporter(repository: accounts);
    final timeSync = SteamTimeSyncService(
      timeClient: timeClient ?? HttpSteamTimeClient(),
      timeProvider: clock,
    );
    final confClient = HttpSteamConfirmationsClient(
      timeProvider: clock,
      serverTimeDiffMs: authenticator.serverTimeDiffMs,
    );
    final confirmations = SteamConfirmationsRepository(
      accounts: accounts,
      client: confClient,
    );
    final sessionLogin = SteamSessionLoginService(
      accounts: accounts,
      authenticator: authenticator,
      loginClient: SteamLoginClient(),
    );
    final biometrics = biometricService ??
        (kIsWeb
            ? const UnavailableBiometricService()
            : LocalAuthBiometricService());

    final services = AppServices._(
      accountsRepository: accounts,
      authenticator: authenticator,
      encryptedAccounts: accounts,
      atRestCipher: atRest,
      secureStorage: storage,
      importer: importer,
      timeSyncService: timeSync,
      biometricService: biometrics,
      confirmationsRepository: confirmations,
      confirmationsClient: confClient,
      sessionLoginService: sessionLogin,
    );

    if (syncServerTimeOnStart) {
      // Best-effort and non-blocking: do not hold Launch Screen for up to 8s.
      // Offline devices keep device-time codes; UI refreshes when sync finishes.
      unawaited(services.syncServerTime(notify: true));
    }

    return services;
  }

  /// Test/helper constructor that keeps everything in memory.
  static Future<AppServices> createInMemory({
    bool encryptAccountsAtRest = true,
    bool seedDemoAccounts = false,
    SteamTimeClient? timeClient,
    BiometricService? biometricService,
    bool syncServerTimeOnStart = false,
  }) {
    return createPrototype(
      encryptAccountsAtRest: encryptAccountsAtRest,
      seedDemoAccounts: seedDemoAccounts,
      secureStorage: PlatformSecureStorage.memory(),
      accountStore: MemoryEncryptedAccountStore(),
      timeClient: timeClient,
      // Tests default to unavailable biometrics so unlock gate stays manual.
      biometricService: biometricService ?? const UnavailableBiometricService(),
      syncServerTimeOnStart: syncServerTimeOnStart,
    );
  }

  /// Removes `mock-*` / known demo profiles left by earlier prototypes.
  static Future<void> _purgeDemoAccounts(
    EncryptedAccountsRepository accounts,
  ) async {
    final profiles = await accounts.listProfiles();
    for (final profile in profiles) {
      if (_isDemoAccountId(profile.id)) {
        await accounts.delete(profile.id);
      }
    }
  }

  static bool _isDemoAccountId(String id) {
    if (id.startsWith('mock-')) return true;
    const known = {
      'mock-primary',
      'mock-trading',
      'mock-alt',
    };
    return known.contains(id);
  }

  /// Enables/disables at-rest AES-GCM and re-wraps all account blobs.
  ///
  /// If preference persistence fails after a successful re-wrap, the account
  /// format is rolled back so UI state can stay consistent with disk.
  Future<void> setEncryptAccountsAtRest(bool enabled) async {
    final previous = _atRestCipher.encryptAtRest;
    if (previous == enabled) {
      notifyListeners();
      return;
    }

    await _encryptedAccounts.setEncryptAtRest(enabled);
    try {
      await _secureStorage.write(
        encryptAtRestPrefKey,
        enabled ? 'true' : 'false',
      );
    } catch (_) {
      // Preference write failed — restore previous on-disk format.
      await _encryptedAccounts.setEncryptAtRest(previous);
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  /// Aligns authenticator clock with Steam QueryTime.
  /// Syncs Steam QueryTime into Guard codes and mobileconf HMAC clocks.
  ///
  /// Concurrent callers share one in-flight request so confirmations refresh
  /// can await startup sync instead of racing with a stale offset.
  Future<SteamTimeSyncResult?> syncServerTime({bool notify = true}) {
    final inFlight = _timeSyncInFlight;
    if (inFlight != null) {
      if (notify && !_timeSyncNotifyRequested) {
        _timeSyncNotifyRequested = true;
        notifyListeners();
      }
      return inFlight;
    }

    _timeSyncNotifyRequested = notify;
    return _timeSyncInFlight = _syncServerTimeBody().whenComplete(() {
      _timeSyncInFlight = null;
      _timeSyncNotifyRequested = false;
    });
  }

  Future<SteamTimeSyncResult?> _syncServerTimeBody() async {
    _timeSyncInProgress = true;
    if (_timeSyncNotifyRequested) notifyListeners();
    try {
      final result = await _timeSyncService.sync();
      _authenticator.serverTimeDiffMs = result.serverTimeDiffMs;
      _confirmationsClient.serverTimeDiffMs = result.serverTimeDiffMs;
      _lastTimeSyncedAt = result.syncedAt;
      _lastTimeSyncError = null;
      return result;
    } catch (error) {
      _lastTimeSyncError = error;
      return null;
    } finally {
      _timeSyncInProgress = false;
      if (_timeSyncNotifyRequested) notifyListeners();
    }
  }

  /// Deletes one account blob and reloads authenticator secrets.
  Future<void> deleteAccount(String accountId) async {
    await accountsRepository.delete(accountId);
    await _reloadAuthenticatorSecrets();
    _bumpAccountsRevision();
    notifyListeners();
  }

  /// Builds a password-encrypted `.sacbak` document of all local accounts.
  ///
  /// The password is independent of Face ID and at-rest master key. Does not
  /// change [encryptAccountsAtRest].
  Future<Uint8List> exportEncryptedBackup({required String password}) async {
    final payloads = await _encryptedAccounts.loadAllPayloads();
    return AccountBackupCodec.encryptBackup(
      accounts: payloads,
      password: password,
    );
  }

  /// Decrypts a `.sacbak` document and merges accounts into the local store.
  ///
  /// Existing accounts with the same id are overwritten. At-rest encryption
  /// preference is left unchanged; restored payloads are re-wrapped with the
  /// current cipher setting.
  Future<BackupRestoreResult> restoreEncryptedBackup({
    required List<int> fileBytes,
    required String password,
  }) async {
    final encryptBefore = encryptAccountsAtRest;
    final contents = await AccountBackupCodec.decryptBackup(
      fileBytes: fileBytes,
      password: password,
    );
    final count = await _encryptedAccounts.restorePayloads(contents.accounts);
    await _reloadAuthenticatorSecrets();
    // Hard guarantee: restore never flips the user's encrypt-at-rest choice.
    if (encryptAccountsAtRest != encryptBefore) {
      await setEncryptAccountsAtRest(encryptBefore);
    }
    _bumpAccountsRevision();
    notifyListeners();
    return BackupRestoreResult(
      restoredCount: count,
      exportedAt: contents.exportedAt,
    );
  }

  /// Loads SteamTools-style account summary for the details sheet.
  ///
  /// When [includeSecrets] is true, also returns Base64 secrets / password for
  /// an explicit owner reveal (the personal-use product decision).
  Future<SteamAccountDetails?> loadAccountDetails(
    String accountId, {
    bool includeSecrets = false,
  }) async {
    final profile = await accountsRepository.getProfile(accountId);
    if (profile == null) return null;

    final meta = await accountsRepository.readPrivateMeta(accountId);
    final secrets = await accountsRepository.readSecrets(accountId);

    final identity = secrets?.identitySecret;
    final password = secrets?.steamPassword;
    final revocation = secrets?.revocationCode;
    final hasRevocation = revocation != null && revocation.trim().isNotEmpty;
    final health = secrets == null
        ? SteamSessionHealth.none
        : SteamMobileSession.evaluateHealth(
            secrets: secrets,
            steamId64: meta?.steamId64,
          );
    return SteamAccountDetails(
      accountId: accountId,
      displayName: profile.nickname,
      loginName: meta?.accountName ?? profile.loginNameHint,
      steamId64: meta?.steamId64,
      serialNumber: meta?.serialNumber,
      deviceId: meta?.deviceId,
      // Recovery code is sensitive — only returned after explicit reveal.
      revocationCode: includeSecrets && hasRevocation ? revocation : null,
      hasRevocationCode: hasRevocation,
      hasIdentitySecret: identity != null && identity.isNotEmpty,
      hasSharedSecret: secrets != null && secrets.sharedSecret.isNotEmpty,
      hasSteamPassword: password != null && password.isNotEmpty,
      hasMobileSession: secrets != null &&
          SteamMobileSession.isUsable(
            secrets: secrets,
            steamId64: meta?.steamId64,
          ),
      sessionHealth: health,
      hasStoredSession: secrets != null &&
          SteamMobileSession.hasStoredSessionMaterial(secrets),
      isDemo: accountId.startsWith('mock-'),
      secretsRevealed: includeSecrets,
      sharedSecretBase64: includeSecrets && secrets != null
          ? base64.encode(secrets.sharedSecret)
          : null,
      identitySecretBase64:
          includeSecrets && identity != null ? base64.encode(identity) : null,
      steamPassword: includeSecrets ? password : null,
    );
  }

  /// Clears Session tokens/cookies for [accountId]. Guard secrets stay.
  ///
  /// When [clearSavedPassword] is true, also drops remembered Steam password.
  Future<bool> clearSteamSession(
    String accountId, {
    bool clearSavedPassword = false,
  }) async {
    final secrets = await _encryptedAccounts.readSecrets(accountId);
    if (secrets == null) return false;
    if (!SteamMobileSession.hasStoredSessionMaterial(secrets) &&
        !(clearSavedPassword &&
            secrets.steamPassword != null &&
            secrets.steamPassword!.isNotEmpty)) {
      return false;
    }
    final next = secrets.withoutSession(clearSavedPassword: clearSavedPassword);
    final ok = await _encryptedAccounts.replaceSecrets(accountId, next);
    if (ok) {
      _bumpAccountsRevision();
      notifyListeners();
    }
    return ok;
  }

  /// Prefill data for the in-app Steam login sheet (username + optional saved password).
  Future<SteamLoginPrefill> steamLoginPrefill(String accountId) async {
    final profile = await accountsRepository.getProfile(accountId);
    final meta = await _encryptedAccounts.readPrivateMeta(accountId);
    final secrets = await _encryptedAccounts.readSecrets(accountId);
    // Prefer private meta account_name; never prefill with nickname-only values.
    final nickname = profile?.nickname.trim() ?? '';
    final fromMeta = SteamLoginClient.sanitizeSteamAccountName(
      meta?.accountName ?? '',
    );
    final fromHint = SteamLoginClient.sanitizeSteamAccountName(
      profile?.loginNameHint ?? '',
    );
    final nickSanitized = SteamLoginClient.sanitizeSteamAccountName(nickname);

    String username = '';
    if (fromMeta.isNotEmpty && !_looksMaskedOrNonLogin(fromMeta)) {
      username = fromMeta;
    } else if (fromHint.isNotEmpty &&
        !_looksMaskedOrNonLogin(fromHint) &&
        // Avoid prefilling a pure display nickname (import without account_name).
        fromHint != nickSanitized) {
      username = fromHint;
    }

    final saved = secrets?.steamPassword;
    return SteamLoginPrefill(
      accountId: accountId,
      displayName: profile?.nickname ?? accountId,
      username: username,
      savedPassword: (saved != null && saved.isNotEmpty) ? saved : null,
    );
  }

  /// Bullet-masked, placeholder, or obviously non-login display strings.
  static bool _looksMaskedOrNonLogin(String value) {
    if (value.contains('•') || value.contains('*') || value.contains('…')) {
      return true;
    }
    if (value.length < 3) return true;
    // Demo / placeholder leftovers.
    if (value.startsWith('mock') || value == 'demo') return true;
    return false;
  }

  /// Password login → persist Session tokens for mobileconf (Method B).
  Future<SteamSessionLoginOutcome> loginSteamSession({
    required String accountId,
    required String username,
    required String password,
    bool rememberPassword = false,
    String? emailCode,
  }) async {
    final outcome = await _sessionLoginService.login(
      accountId: accountId,
      username: username,
      password: password,
      rememberPassword: rememberPassword,
      emailCode: emailCode,
    );
    if (outcome is SteamSessionLoginOk) {
      accountsRevision.value = accountsRevision.value + 1;
      notifyListeners();
    }
    return outcome;
  }

  /// Completes email Steam Guard step after [loginSteamSession] requested it.
  Future<SteamSessionLoginOutcome> continueSteamSessionEmailCode({
    required String accountId,
    required int clientId,
    required List<int> requestId,
    required int steamId,
    required String emailCode,
    String? username,
    String? password,
    bool rememberPassword = false,
  }) async {
    final outcome = await _sessionLoginService.continueWithEmailCode(
      accountId: accountId,
      clientId: clientId,
      requestId: requestId,
      steamId: steamId,
      emailCode: emailCode,
      username: username,
      password: password,
      rememberPassword: rememberPassword,
    );
    if (outcome is SteamSessionLoginOk) {
      accountsRevision.value = accountsRevision.value + 1;
      notifyListeners();
    }
    return outcome;
  }

  /// Imports one or more maFile JSON documents, reloads authenticator secrets,
  /// and notifies listeners so the UI can refresh account lists.
  Future<ImportResult> importMaFileJson(
    String source, {
    String? sourceLabel,
  }) async {
    final result = await _importer.importJsonString(
      source,
      sourceLabel: sourceLabel,
    );
    if (result.hasSuccess) {
      await _reloadAuthenticatorSecrets();
      _bumpAccountsRevision();
      notifyListeners();
    }
    return result;
  }

  Future<ImportResult> importMaFileJsonBatch(
    List<({String source, String? label})> items,
  ) async {
    final result = await _importer.importJsonStrings(items);
    if (result.hasSuccess) {
      await _reloadAuthenticatorSecrets();
      _bumpAccountsRevision();
      notifyListeners();
    }
    return result;
  }

  Future<void> _reloadAuthenticatorSecrets() async {
    final secrets = await _encryptedAccounts.loadSharedSecretsByAccountId();
    _authenticator.replaceSharedSecrets(secrets);
  }

  void _bumpAccountsRevision() {
    accountsRevision.value = accountsRevision.value + 1;
  }
}

/// Prefill for the Steam login sheet (presentation-safe; no secret type leaks).
class SteamLoginPrefill {
  const SteamLoginPrefill({
    required this.accountId,
    required this.displayName,
    required this.username,
    this.savedPassword,
  });

  final String accountId;
  final String displayName;
  final String username;

  /// Plain password only when user previously chose “记住密码”.
  final String? savedPassword;
}

/// Outcome of merging a `.sacbak` into the local store.
class BackupRestoreResult {
  const BackupRestoreResult({
    required this.restoredCount,
    this.exportedAt,
  });

  final int restoredCount;
  final String? exportedAt;
}
