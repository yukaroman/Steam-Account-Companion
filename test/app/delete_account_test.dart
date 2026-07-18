import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/app/app_services.dart';
import 'package:steam_account_companion/features/authenticator/data/steam_guard_authenticator_service.dart';

void main() {
  test('deleteAccount removes profile and authenticator secret', () async {
    final services = await AppServices.createInMemory(
      seedDemoAccounts: true,
      syncServerTimeOnStart: false,
    );
    final profiles = await services.accountsRepository.listProfiles();
    expect(profiles, isNotEmpty);
    final id = profiles.first.id;
    final auth =
        services.authenticatorService as SteamGuardAuthenticatorService;
    expect(auth.hasSecretFor(id), isTrue);

    await services.deleteAccount(id);

    expect(await services.accountsRepository.getProfile(id), isNull);
    expect(auth.hasSecretFor(id), isFalse);
  });
}
