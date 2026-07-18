import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_spacing.dart';

abstract final class AppTheme {
  static ThemeData dark({bool oled = false}) {
    final background = oled ? Colors.black : AppColors.ink;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.cyan,
      brightness: Brightness.dark,
      surface: background,
      primary: AppColors.cyan,
      secondary: AppColors.blue,
      tertiary: AppColors.violet,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: background,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.graphite.withValues(alpha: 0.92),
        indicatorColor: AppColors.cyan.withValues(alpha: 0.16),
        elevation: 0,
        height: 78,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.cyan
                : AppColors.slate,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.cyan
                : AppColors.slate,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.35,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      brightness: Brightness.light,
      surface: AppColors.mist,
      primary: AppColors.blue,
      secondary: AppColors.violet,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: AppColors.mist,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.96),
        indicatorColor: AppColors.blue.withValues(alpha: 0.12),
        elevation: 0,
        height: 78,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.blue
                : AppColors.slateLight,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.blue
                : AppColors.slateLight,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.35,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.4,
          height: 1.05,
          color: isDark ? AppColors.softWhite : const Color(0xFF10141C),
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.9,
          height: 1.15,
          color: isDark ? AppColors.softWhite : const Color(0xFF10141C),
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
          color: isDark ? AppColors.softWhite : const Color(0xFF151A23),
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.15,
          color: isDark ? AppColors.softWhite : const Color(0xFF151A23),
        ),
        bodyLarge: TextStyle(
          height: 1.45,
          color: isDark
              ? AppColors.softWhite.withValues(alpha: 0.92)
              : const Color(0xFF2A3342),
        ),
        bodyMedium: TextStyle(
          height: 1.42,
          color: isDark
              ? AppColors.softWhite.withValues(alpha: 0.88)
              : const Color(0xFF3A4556),
        ),
        labelLarge: const TextStyle(fontWeight: FontWeight.w700),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        side: BorderSide(color: isDark ? AppColors.line : AppColors.lineLight),
        // Room for CJK labels; tight padding clipped 全部/登录/交易 on web.
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          height: 1.3,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.lineSoft : AppColors.lineLight,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppColors.elevatedHigh : const Color(0xFF1B2230),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        elevation: 8,
      ),
    );
  }
}
