import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.emphasized = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = AppColors.panelBackground(context);
    final borderColor = emphasized
        ? AppColors.cyan.withValues(alpha: dark ? 0.35 : 0.28)
        : AppColors.border(context);

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.28 : 0.06),
            blurRadius: emphasized ? 36 : 24,
            offset: const Offset(0, 14),
          ),
          if (emphasized)
            BoxShadow(
              color: AppColors.cyan.withValues(alpha: dark ? 0.08 : 0.05),
              blurRadius: 40,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Material(
        color: background,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: BorderSide(
            color: borderColor,
            width: emphasized ? 1.2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          splashColor: AppColors.cyan.withValues(alpha: 0.08),
          highlightColor: AppColors.cyan.withValues(alpha: 0.04),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    if (onTap == null) return panel;
    return Semantics(button: true, child: panel);
  }
}
