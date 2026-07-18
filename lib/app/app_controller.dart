import 'package:flutter/material.dart';

import '../features/settings/data/theme_preferences.dart';
import 'app_services.dart';

class AppController extends ChangeNotifier {
  AppController({
    AppServices? services,
    ThemePreferences? themePreferences,
    ThemeMode themeMode = ThemeMode.system,
    bool oledMode = false,
    bool faceIdEnabled = false,
    String autoLock = ThemePreferences.autoLockDefault,
  })  : _services = services,
        _themePreferences = themePreferences,
        _themeMode = themeMode,
        _oledMode = oledMode,
        _faceIdEnabled = faceIdEnabled,
        _autoLock = autoLock,
        // Only require unlock gate when Face ID is enabled.
        _unlocked = !faceIdEnabled;

  AppServices? _services;
  ThemePreferences? _themePreferences;

  ThemeMode _themeMode;
  bool _oledMode;
  bool _faceIdEnabled;
  String _autoLock;
  bool _unlocked;
  bool _encryptAccountsAtRest = true;
  bool _encryptToggleBusy = false;
  DateTime? _pausedAt;

  /// Ignore brief inactive / re-lock for a moment after a successful unlock
  /// (iOS often emits inactive→resumed right after auth UI).
  DateTime? _unlockGraceUntil;

  static const _unlockGrace = Duration(seconds: 2);

  ThemeMode get themeMode => _themeMode;
  bool get oledMode => _oledMode;
  bool get faceIdEnabled => _faceIdEnabled;
  String get autoLock => _autoLock;
  bool get unlocked => _unlocked;

  /// At-rest AES-GCM for account payloads. Default on; can be turned off.
  bool get encryptAccountsAtRest => _encryptAccountsAtRest;
  bool get encryptToggleBusy => _encryptToggleBusy;

  bool get _inUnlockGrace {
    final until = _unlockGraceUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Attach services after async bootstrap (keeps encryption flag in sync).
  void bindServices(AppServices? services) {
    _services = services;
    final enabled = services?.encryptAccountsAtRest ?? false;
    if (_encryptAccountsAtRest != enabled) {
      _encryptAccountsAtRest = enabled;
      notifyListeners();
    }
  }

  void bindThemePreferences(ThemePreferences? preferences) {
    _themePreferences = preferences;
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    await _themePreferences?.saveThemeMode(value);
  }

  Future<void> setOledMode(bool value) async {
    if (_oledMode == value) return;
    _oledMode = value;
    notifyListeners();
    await _themePreferences?.saveOledMode(value);
  }

  /// When enabled, next cold start shows unlock. Turning off clears the gate.
  Future<void> setFaceIdEnabled(bool value) async {
    if (_faceIdEnabled == value) return;
    _faceIdEnabled = value;
    if (!value && !_unlocked) {
      // Disabling Face ID should not leave the user stuck on the lock screen.
      _unlocked = true;
    }
    notifyListeners();
    await _themePreferences?.saveFaceIdEnabled(value);
  }

  Future<void> setAutoLock(String value) async {
    if (_autoLock == value) return;
    if (!ThemePreferences.autoLockOptions.contains(value)) return;
    _autoLock = value;
    notifyListeners();
    await _themePreferences?.saveAutoLock(value);
  }

  Future<void> setEncryptAccountsAtRest(bool value) async {
    if (_encryptAccountsAtRest == value || _encryptToggleBusy) return;
    final services = _services;
    _encryptToggleBusy = true;
    notifyListeners();
    try {
      if (services != null) {
        await services.setEncryptAccountsAtRest(value);
        // Always mirror the store's actual state after the attempt.
        _encryptAccountsAtRest = services.encryptAccountsAtRest;
      } else {
        _encryptAccountsAtRest = value;
      }
    } catch (_) {
      if (services != null) {
        _encryptAccountsAtRest = services.encryptAccountsAtRest;
      }
      rethrow;
    } finally {
      _encryptToggleBusy = false;
      notifyListeners();
    }
  }

  void unlock() {
    _unlocked = true;
    _pausedAt = null;
    _unlockGraceUntil = DateTime.now().add(_unlockGrace);
    notifyListeners();
  }

  /// Always available from settings — independent of Face ID.
  void lock() {
    _unlocked = false;
    _unlockGraceUntil = null;
    notifyListeners();
  }

  /// Call from [WidgetsBindingObserver] for auto-lock.
  ///
  /// No full-screen black privacy cover: that left a black screen when
  /// backgrounding / returning with Face ID on. Protection is UnlockPage
  /// after a real lock (immediate or timed).
  void handleAppLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // Control Center / app switcher peek: do nothing.
        // Covering with black caused stuck black frames; locking here caused thrash.
        return;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _onReallyBackgrounded();
        return;
      case AppLifecycleState.resumed:
        _onEnterForeground();
        return;
      case AppLifecycleState.detached:
        return;
    }
  }

  /// Test hook: pretend the app was backgrounded at [when].
  @visibleForTesting
  void debugSetPausedAt(DateTime when) {
    _pausedAt = when;
  }

  /// Test hook: end post-unlock grace so lifecycle can lock again.
  @visibleForTesting
  void debugClearUnlockGrace() {
    _unlockGraceUntil = null;
  }

  /// True background — start auto-lock timer / immediate lock.
  void _onReallyBackgrounded() {
    if (!_faceIdEnabled) return;
    if (_inUnlockGrace) return;

    _pausedAt ??= DateTime.now();

    if (_autoLock == ThemePreferences.autoLockImmediate && _unlocked) {
      _unlocked = false;
      notifyListeners();
      return;
    }
    // Timed / never: only record pause; lock decision on resume.
  }

  void _onEnterForeground() {
    if (!_faceIdEnabled) {
      _pausedAt = null;
      return;
    }

    if (_inUnlockGrace) {
      // Stay on home after a successful unlock; ignore flaky lifecycle.
      _pausedAt = null;
      return;
    }

    if (_autoLock == ThemePreferences.autoLockNever) {
      // Cold-start still locks via constructor; resume does not re-lock.
      _pausedAt = null;
      return;
    }

    if (_autoLock == ThemePreferences.autoLockImmediate) {
      // Already locked when backgrounded (if grace had ended).
      _pausedAt = null;
      return;
    }

    // Timed auto-lock.
    final paused = _pausedAt;
    _pausedAt = null;
    final threshold = ThemePreferences.autoLockDuration(_autoLock);
    if (threshold != null &&
        paused != null &&
        DateTime.now().difference(paused) >= threshold &&
        _unlocked) {
      _unlocked = false;
      notifyListeners();
    }
  }
}
