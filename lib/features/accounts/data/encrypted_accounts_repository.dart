import '../../../core/security/account_cipher.dart';
import '../../../core/security/account_integrity_exception.dart';
import '../../../core/security/account_payload_codec.dart';
import '../../../core/security/at_rest_account_cipher.dart';
import '../../../core/security/encrypted_account_store.dart';
import '../domain/accounts_repository.dart';
import '../models/steam_account_payload.dart';
import '../models/steam_account_private_meta.dart';
import '../models/steam_account_profile.dart';
import '../models/steam_account_secrets.dart';

/// Local accounts repository. Payloads pass through [AccountCipher] before save.
///
/// At-rest encryption is **on by default** via [AtRestAccountCipher]. Advanced
/// users may disable it; the class name keeps the encrypted-store boundary
/// even when the active cipher is temporarily pass-through plain JSON.
class EncryptedAccountsRepository implements AccountsRepository {
  EncryptedAccountsRepository({
    required EncryptedAccountStore store,
    required AccountCipher cipher,
  })  : _store = store,
        _cipher = cipher;

  final EncryptedAccountStore _store;
  final AccountCipher _cipher;

  /// Whether new writes are encrypted. Only meaningful with [AtRestAccountCipher].
  bool get encryptAtRest {
    final cipher = _cipher;
    return cipher is AtRestAccountCipher && cipher.encryptAtRest;
  }

  @override
  Future<List<SteamAccountProfile>> listProfiles() async {
    final ids = await _store.listAccountIds();
    final profiles = <SteamAccountProfile>[];
    for (final id in ids) {
      final profile = await getProfile(id);
      if (profile != null) profiles.add(profile);
    }
    profiles.sort((a, b) {
      final byName =
          a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return profiles;
  }

  @override
  Future<SteamAccountProfile?> getProfile(String accountId) async {
    final payload = await _readPayload(accountId);
    return payload?.profile;
  }

  @override
  Future<void> upsert({
    required SteamAccountProfile profile,
    required SteamAccountSecrets secrets,
    SteamAccountPrivateMeta privateMeta = const SteamAccountPrivateMeta(),
  }) async {
    if (profile.id.isEmpty) {
      throw ArgumentError.value(profile.id, 'profile.id', 'must not be empty');
    }
    final payload = SteamAccountPayload(
      profile: profile,
      privateMeta: privateMeta,
      secrets: secrets,
    );
    final plaintext = AccountPayloadCodec.encode(payload);
    final ciphertext = await _cipher.encrypt(
      plaintext,
      accountId: profile.id,
    );
    await _store.save(accountId: profile.id, encryptedPayload: ciphertext);
  }

  @override
  Future<void> delete(String accountId) => _store.delete(accountId);

  @override
  Future<SteamAccountSecrets?> readSecrets(String accountId) async {
    final payload = await _readPayload(accountId);
    return payload?.secrets;
  }

  /// Replaces secrets while keeping profile + private meta. Domain/infra only.
  ///
  /// Used after JWT access-token refresh so cookies stay in sync at rest.
  Future<bool> replaceSecrets(
    String accountId,
    SteamAccountSecrets secrets,
  ) async {
    final payload = await _readPayload(accountId);
    if (payload == null) return false;
    await upsert(
      profile: payload.profile,
      privateMeta: payload.privateMeta,
      secrets: secrets,
    );
    return true;
  }

  @override
  Future<SteamAccountPrivateMeta?> readPrivateMeta(String accountId) async {
    final payload = await _readPayload(accountId);
    return payload?.privateMeta;
  }

  /// Loads every account's shared_secret for authenticator bootstrap.
  ///
  /// Domain/infra only — do not expose the returned map to widgets.
  Future<Map<String, List<int>>> loadSharedSecretsByAccountId() async {
    final ids = await _store.listAccountIds();
    final result = <String, List<int>>{};
    for (final id in ids) {
      final secrets = await readSecrets(id);
      if (secrets != null) {
        result[id] = List<int>.from(secrets.sharedSecret);
      }
    }
    return result;
  }

  /// Full payloads for encrypted backup. Domain/infra only — never pass to UI.
  Future<List<SteamAccountPayload>> loadAllPayloads() async {
    final ids = await _store.listAccountIds();
    final payloads = <SteamAccountPayload>[];
    for (final id in ids) {
      final payload = await _readPayload(id);
      if (payload != null) payloads.add(payload);
    }
    return payloads;
  }

  /// Restores payloads via upsert (merge). Does not change encrypt-at-rest mode.
  ///
  /// Encrypts all payloads first, then writes. On write failure, previously
  /// overwritten blobs for this batch are rolled back to their prior bytes.
  Future<int> restorePayloads(List<SteamAccountPayload> payloads) async {
    if (payloads.isEmpty) return 0;

    // Snapshot existing ciphertext for rollback.
    final previous = <String, List<int>?>{};
    for (final payload in payloads) {
      final id = payload.profile.id;
      if (id.isEmpty) {
        throw ArgumentError.value(id, 'profile.id', 'must not be empty');
      }
      previous[id] = await _store.read(id);
    }

    // Pre-validate + encrypt every payload before any disk mutation.
    final prepared = <({String id, List<int> bytes})>[];
    for (final payload in payloads) {
      final plaintext = AccountPayloadCodec.encode(payload);
      final wrapped = await _cipher.encrypt(
        plaintext,
        accountId: payload.profile.id,
      );
      prepared.add((id: payload.profile.id, bytes: wrapped));
    }

    try {
      for (final item in prepared) {
        await _store.save(
          accountId: item.id,
          encryptedPayload: item.bytes,
        );
      }
    } catch (_) {
      for (final entry in previous.entries) {
        final prior = entry.value;
        if (prior == null) {
          await _store.delete(entry.key);
        } else {
          await _store.save(
            accountId: entry.key,
            encryptedPayload: prior,
          );
        }
      }
      rethrow;
    }
    return prepared.length;
  }

  Future<SteamAccountPayload?> _readPayload(String accountId) async {
    final ciphertext = await _store.read(accountId);
    if (ciphertext == null) return null;
    final plaintext = await _cipher.decrypt(
      ciphertext,
      accountId: accountId,
    );
    final payload = AccountPayloadCodec.decode(plaintext);
    if (payload.profile.id != accountId) {
      throw const AccountIntegrityException(
        AccountIntegrityException.payloadIdMismatch,
        'stored payload id does not match account key',
      );
    }
    return payload;
  }

  /// Turns at-rest encryption on/off and re-wraps every stored account.
  Future<void> setEncryptAtRest(bool enabled) async {
    final cipher = _cipher;
    if (cipher is! AtRestAccountCipher) {
      throw StateError(
        'setEncryptAtRest requires AtRestAccountCipher, got ${cipher.runtimeType}',
      );
    }
    if (cipher.encryptAtRest == enabled) return;

    final ids = await _store.listAccountIds();
    final payloads = <SteamAccountPayload>[];
    for (final id in ids) {
      final payload = await _readPayload(id);
      if (payload != null) payloads.add(payload);
    }

    cipher.encryptAtRest = enabled;

    for (final payload in payloads) {
      final plaintext = AccountPayloadCodec.encode(payload);
      final wrapped = await _cipher.encrypt(
        plaintext,
        accountId: payload.profile.id,
      );
      await _store.save(
        accountId: payload.profile.id,
        encryptedPayload: wrapped,
      );
    }
  }
}
