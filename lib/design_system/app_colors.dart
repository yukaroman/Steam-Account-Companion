import 'package:flutter/material.dart';

abstract final class AppColors {
  // Dark canvas
  static const ink = Color(0xFF07090E);
  static const graphite = Color(0xFF0E1219);
  static const elevated = Color(0xFF141A24);
  static const elevatedHigh = Color(0xFF1B2330);
  static const line = Color(0xFF2A3344);
  static const lineSoft = Color(0xFF1F2735);

  // Light canvas
  static const mist = Color(0xFFF4F6FB);
  static const cloud = Color(0xFFFFFFFF);
  static const lineLight = Color(0xFFE4E9F2);
  static const slateLight = Color(0xFF6B7689);

  // Text
  static const slate = Color(0xFF8B96A8);
  static const softWhite = Color(0xFFF7F9FC);

  // Brand accents
  static const cyan = Color(0xFF5CE1FF);
  static const blue = Color(0xFF6B8CFF);
  static const violet = Color(0xFF9B87FF);
  static const success = Color(0xFF3DDC97);
  static const warning = Color(0xFFFFC857);
  static const danger = Color(0xFFFF6B81);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, blue, violet],
  );

  static const brandGradientSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x335CE1FF),
      Color(0x286B8CFF),
      Color(0x229B87FF),
    ],
  );

  static Color panelBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? elevated.withValues(alpha: 0.94) : cloud;
  }

  static Color border(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? line.withValues(alpha: 0.85) : lineLight;
  }

  static Color mutedText(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? slate : slateLight;
  }
}
