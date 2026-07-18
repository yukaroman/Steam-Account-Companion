import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Subtle ambient glow behind page content for a premium dark-first look.
class SoftBackground extends StatelessWidget {
  const SoftBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
        ),
        if (isDark) ...[
          Positioned(
            top: -80,
            right: -40,
            child: _GlowOrb(
              diameter: 220,
              color: AppColors.blue.withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            top: 180,
            left: -90,
            child: _GlowOrb(
              diameter: 260,
              color: AppColors.violet.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            bottom: 80,
            right: -60,
            child: _GlowOrb(
              diameter: 180,
              color: AppColors.cyan.withValues(alpha: 0.08),
            ),
          ),
        ] else ...[
          Positioned(
            top: -60,
            right: -20,
            child: _GlowOrb(
              diameter: 200,
              color: AppColors.blue.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            top: 220,
            left: -80,
            child: _GlowOrb(
              diameter: 220,
              color: AppColors.violet.withValues(alpha: 0.08),
            ),
          ),
        ],
        Positioned.fill(child: child),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
