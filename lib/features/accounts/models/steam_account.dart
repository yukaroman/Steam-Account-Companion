import 'package:flutter/material.dart';

import 'steam_account_profile.dart';

/// Presentation-facing account card model.
///
/// Prefer building from [SteamAccountProfile] so secrets never enter the UI.
class SteamAccount {
  const SteamAccount({
    required this.id,
    required this.nickname,
    required this.loginNameHint,
    required this.avatarColor,
    required this.initials,
  });

  final String id;
  final String nickname;
  final String loginNameHint;
  final Color avatarColor;
  final String initials;

  factory SteamAccount.fromProfile(SteamAccountProfile profile) {
    return SteamAccount(
      id: profile.id,
      nickname: profile.nickname,
      loginNameHint: profile.loginNameHint,
      avatarColor: Color(profile.avatarColorValue),
      initials: profile.initials,
    );
  }
}
