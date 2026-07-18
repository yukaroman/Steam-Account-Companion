import 'package:flutter/material.dart';

import 'app_spacing.dart';

class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.label,
    required this.color,
    this.compact = false,
    super.key,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        // Extra vertical room so Chinese glyphs (高风险 / 注意) are not clipped.
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        softWrap: false,
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w800,
          height: 1.2,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
