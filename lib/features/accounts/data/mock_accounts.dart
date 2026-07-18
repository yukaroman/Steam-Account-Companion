import '../models/steam_account.dart';
import 'demo_accounts_seed.dart';

/// UI fixture accounts, kept in sync with [DemoAccountsSeed] profiles.
final mockAccounts = <SteamAccount>[
  for (final profile in DemoAccountsSeed.profiles)
    SteamAccount.fromProfile(profile),
];
