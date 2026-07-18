import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists appearance + lock preferences (SharedPreferences; works on Chrome).
class ThemePreferences {
  ThemePreferences(this._prefs);

  static const themeModeKey = 'pref_theme_mode';
  static const oledModeKey = 'pref_oled_mode';
  static const faceIdKey = 'pref_face_id';
  static const autoLockKey = 'pref_auto_lock';

  /// UI labels, also stored as preference values.
  static const autoLockNever = '从不';
  static const autoLockImmediate = '立即';
  static const autoLockOneMinute = '1 分钟';
  static const autoLockFiveMinutes = '5 分钟';
  static const autoLockThirtyMinutes = '30 分钟';
  static const autoLockOneHour = '1 小时';
  static const autoLockEightHours = '8 小时';
  static const autoLockTwentyFourHours = '24 小时';

  /// Longest timed option — default so background re-lock is rare.
  static const autoLockDefault = autoLockTwentyFourHours;

  static const autoLockOptions = [
    autoLockNever,
    autoLockImmediate,
    autoLockOneMinute,
    autoLockFiveMinutes,
    autoLockThirtyMinutes,
    autoLockOneHour,
    autoLockEightHours,
    autoLockTwentyFourHours,
  ];

  /// How long the app may stay in background before resume requires unlock.
  /// Null means never (no timed re-lock) or immediate (handled separately).
  static Duration? autoLockDuration(String value) {
    return switch (value) {
      autoLockNever => null,
      autoLockImmediate => Duration.zero,
      autoLockOneMinute => const Duration(minutes: 1),
      autoLockFiveMinutes => const Duration(minutes: 5),
      autoLockThirtyMinutes => const Duration(minutes: 30),
      autoLockOneHour => const Duration(hours: 1),
      autoLockEightHours => const Duration(hours: 8),
      autoLockTwentyFourHours => const Duration(hours: 24),
      _ => const Duration(hours: 24),
    };
  }

  final SharedPreferences _prefs;

  static Future<ThemePreferences> open() async {
    final prefs = await SharedPreferences.getInstance();
    return ThemePreferences(prefs);
  }

  ThemeMode loadThemeMode({ThemeMode fallback = ThemeMode.system}) {
    final raw = _prefs.getString(themeModeKey);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => fallback,
    };
  }

  bool loadOledMode({bool fallback = false}) {
    return _prefs.getBool(oledModeKey) ?? fallback;
  }

  /// Default **false** — unlock gate only when user opts in.
  bool loadFaceIdEnabled({bool fallback = false}) {
    return _prefs.getBool(faceIdKey) ?? fallback;
  }

  /// Default **24 小时** — only re-lock after a long time in background.
  String loadAutoLock({String fallback = autoLockDefault}) {
    final raw = _prefs.getString(autoLockKey);
    if (raw != null && autoLockOptions.contains(raw)) return raw;
    return fallback;
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(themeModeKey, value);
  }

  Future<void> saveOledMode(bool enabled) async {
    await _prefs.setBool(oledModeKey, enabled);
  }

  Future<void> saveFaceIdEnabled(bool enabled) async {
    await _prefs.setBool(faceIdKey, enabled);
  }

  Future<void> saveAutoLock(String value) async {
    await _prefs.setString(autoLockKey, value);
  }
}
