import '../../authenticator/data/steam_guard_authenticator_service.dart';
import '../domain/accounts_repository.dart';
import '../models/steam_account_private_meta.dart';
import '../models/steam_account_profile.dart';
import '../models/steam_account_secrets.dart';

/// Seeds the encrypted repository with the three prototype accounts.
///
/// Secrets come from [DemoSteamGuardSecrets] and cannot log into Steam.
abstract final class DemoAccountsSeed {
  static const profiles = <SteamAccountProfile>[
    SteamAccountProfile(
      id: 'mock-primary',
      nickname: 'demo_primary',
      loginNameHint: 'demo_primary',
      initials: 'D',
      avatarColorValue: 0xFF6B8CFF,
    ),
    SteamAccountProfile(
      id: 'mock-trading',
      nickname: 'demo_trading',
      loginNameHint: 'demo_trading',
      initials: 'D',
      avatarColorValue: 0xFF9B87FF,
    ),
    SteamAccountProfile(
      id: 'mock-alt',
      nickname: 'demo_alt',
      loginNameHint: 'demo_alt',
      initials: 'D',
      avatarColorValue: 0xFF3DDC97,
    ),
  ];

  static const privateMetaById = <String, SteamAccountPrivateMeta>{
    'mock-primary': SteamAccountPrivateMeta(
      accountName: 'demo_primary',
      deviceId: 'android:00000000-0000-4000-8000-000000000001',
    ),
    'mock-trading': SteamAccountPrivateMeta(
      accountName: 'demo_trading',
      deviceId: 'android:00000000-0000-4000-8000-000000000002',
    ),
    'mock-alt': SteamAccountPrivateMeta(
      accountName: 'demo_alt',
      deviceId: 'android:00000000-0000-4000-8000-000000000003',
    ),
  };

  static Future<void> seed(AccountsRepository repository) async {
    for (final profile in profiles) {
      final secretB64 = DemoSteamGuardSecrets.byAccountId[profile.id];
      if (secretB64 == null) {
        throw StateError('Missing demo secret for ${profile.id}');
      }
      await repository.upsert(
        profile: profile,
        privateMeta:
            privateMetaById[profile.id] ?? const SteamAccountPrivateMeta(),
        secrets: SteamAccountSecrets.fromBase64(sharedSecretBase64: secretB64),
      );
    }
  }
}
