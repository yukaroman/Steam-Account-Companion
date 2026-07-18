abstract interface class SteamClient {
  Future<SteamSessionState> sessionState();
  Future<void> refreshSession();
}

enum SteamSessionState { anonymous, valid, expired, refreshing }
