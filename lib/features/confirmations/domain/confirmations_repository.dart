import '../models/steam_confirmation.dart';

abstract interface class ConfirmationsRepository {
  /// Pending confirmations across accounts that have session + identity_secret.
  Future<List<SteamConfirmation>> pending();

  Future<void> approve(SteamConfirmation confirmation);

  Future<void> reject(SteamConfirmation confirmation);
}
