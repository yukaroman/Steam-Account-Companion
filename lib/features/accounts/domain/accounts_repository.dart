import '../models/steam_account_private_meta.dart';
import '../models/steam_account_profile.dart';
import '../models/steam_account_secrets.dart';

/// Local account catalog. Presentation only consumes [SteamAccountProfile].
abstract interface class AccountsRepository {
  Future<List<SteamAccountProfile>> listProfiles();

  Future<SteamAccountProfile?> getProfile(String accountId);

  Future<void> upsert({
    required SteamAccountProfile profile,
    required SteamAccountSecrets secrets,
    SteamAccountPrivateMeta privateMeta,
  });

  Future<void> delete(String accountId);

  /// Domain/infra only — used by authenticator code, never by widgets.
  Future<SteamAccountSecrets?> readSecrets(String accountId);

  /// Domain/infra only — device identity and Steam identifiers.
  Future<SteamAccountPrivateMeta?> readPrivateMeta(String accountId);
}
