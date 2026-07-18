import 'package:flutter/material.dart';

import '../features/lock/presentation/unlock_page.dart';
import '../features/settings/data/theme_preferences.dart';
import 'app_controller.dart';
import 'app_services.dart';
import 'home_shell.dart';
import 'theme.dart';

class SteamCompanionApp extends StatefulWidget {
  const SteamCompanionApp({
    super.key,
    this.services,
    this.themePreferences,
    this.initialThemeMode = ThemeMode.system,
    this.initialOledMode = false,
    this.initialFaceIdEnabled = false,
    this.initialAutoLock = ThemePreferences.autoLockDefault,
  });

  /// Optional composition root. When null, pages fall back to empty defaults.
  final AppServices? services;

  /// Optional preference store. When null, lock/theme changes are in-memory only.
  final ThemePreferences? themePreferences;

  final ThemeMode initialThemeMode;
  final bool initialOledMode;
  final bool initialFaceIdEnabled;
  final String initialAutoLock;

  @override
  State<SteamCompanionApp> createState() => _SteamCompanionAppState();
}

class _SteamCompanionAppState extends State<SteamCompanionApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late final AppController _controller = AppController(
    services: widget.services,
    themePreferences: widget.themePreferences,
    themeMode: widget.initialThemeMode,
    oledMode: widget.initialOledMode,
    faceIdEnabled: widget.initialFaceIdEnabled,
    autoLock: widget.initialAutoLock,
  );

  /// Tracks unlock→lock transitions so we can dismiss overlays above [HomeShell].
  late bool _wasUnlocked = _controller.unlocked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.bindServices(widget.services);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant SteamCompanionApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services != widget.services) {
      _controller.bindServices(widget.services);
    }
    if (oldWidget.themePreferences != widget.themePreferences) {
      _controller.bindThemePreferences(widget.themePreferences);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final unlocked = _controller.unlocked;
    if (_wasUnlocked && !unlocked) {
      // Lock transition: drop modals/dialogs so revealed secrets cannot sit
      // above the unlock gate (routes live on the root Navigator under home).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = _navigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.popUntil((route) => route.isFirst);
        }
      });
    }
    _wasUnlocked = unlocked;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.handleAppLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final unlocked = _controller.unlocked;

        return MaterialApp(
          title: 'Steam Companion',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(oled: _controller.oledMode),
          themeMode: _controller.themeMode,
          // Home stays mounted so unlock does not remount + reload accounts.
          home: HomeShell(
            key: const ValueKey('home'),
            controller: _controller,
            services: widget.services,
          ),
          // Unlock gate sits *above* the root Navigator (builder child), so it
          // covers bottom sheets / dialogs / pushed routes — not only home.
          builder: (context, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                TickerMode(
                  enabled: unlocked,
                  child: Offstage(
                    offstage: !unlocked,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
                if (!unlocked)
                  UnlockPage(
                    key: const ValueKey('unlock'),
                    faceIdEnabled: _controller.faceIdEnabled,
                    biometricService: widget.services?.biometricService,
                    onUnlocked: _controller.unlock,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
