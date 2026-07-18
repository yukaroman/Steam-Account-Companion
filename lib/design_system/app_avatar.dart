import 'package:flutter/material.dart';

import '../features/accounts/models/steam_account.dart';
import 'app_colors.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.account,
    this.size = 40,
    this.showRing = false,
    super.key,
  });

  final SteamAccount account;
  final double size;
  final bool showRing;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.34);
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            account.avatarColor,
            Color.lerp(account.avatarColor, Colors.black, 0.22)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: account.avatarColor.withValues(alpha: 0.28),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: Text(
        account.initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
    );

    if (!showRing) return avatar;

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.4),
        gradient: AppColors.brandGradient,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(size * 0.38),
        ),
        padding: const EdgeInsets.all(2),
        child: avatar,
      ),
    );
  }
}
