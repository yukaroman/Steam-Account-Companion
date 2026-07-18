import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'design_system/app_colors.dart';
import 'features/settings/data/theme_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register this app's GPL text alongside dependency licenses shown from Settings.
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('LICENSE');
    yield LicenseEntryWithLineBreaks(
      const ['Steam Account Companion'],
      license,
    );
  });

  // Keep uncaught errors from taking down the process without a chance to paint
  // UI, but never write exception details or stack traces in release builds.
  FlutterError.onError = (details) {
    if (kDebugMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  // Paint a branded shell immediately — do not await storage first
  // (that was the long white screen on cold start).
  runApp(const _BootstrapApp());
}

/// Loads prefs + services off the first frame, then swaps to [SteamCompanionApp].
class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  Widget? _ready;
  Object? _error;
  var _booting = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (mounted) {
      setState(() {
        _booting = true;
        _error = null;
        _ready = null;
      });
    }
    try {
      final themePreferences = await ThemePreferences.open();
      final services = await AppServices.createPrototype(
        // Never auto-seed demos on cold start — even in debug. Seeding mixed with
        // real Keychain state and force-kill/reopen caused confusing crashes/UX.
        // Use AppServices.createInMemory(seedDemoAccounts: true) in tests only.
        seedDemoAccounts: false,
        syncServerTimeOnStart: !kIsWeb,
      );
      if (!mounted) return;
      setState(() {
        _ready = SteamCompanionApp(
          services: services,
          themePreferences: themePreferences,
          initialThemeMode: themePreferences.loadThemeMode(),
          initialOledMode: themePreferences.loadOledMode(),
          initialFaceIdEnabled: themePreferences.loadFaceIdEnabled(),
          initialAutoLock: themePreferences.loadAutoLock(),
        );
        _booting = false;
        _error = null;
      });
    } catch (error, stack) {
      if (kDebugMode) debugPrint('Startup failed: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _error = error;
        _booting = false;
        _ready = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready != null) return _ready!;

    final isDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;

    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: isDark ? AppColors.ink : AppColors.mist,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 40,
                    color: isDark ? AppColors.danger : const Color(0xFFC62828),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '启动失败',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.softWhite
                          : const Color(0xFF151A23),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    '$_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? AppColors.slate : AppColors.slateLight,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _booting ? null : _boot,
                    child: Text(_booting ? '重试中…' : '重试'),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 12),
                    Text(
                      '提示：Debug 安装后若从桌面图标冷启动闪退，可改用\n'
                      'flutter run --release 做真机验收。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.slate : AppColors.slateLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Match app chrome so cold start is not a long white flash.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: isDark ? AppColors.ink : AppColors.mist,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.cyan,
          brightness: isDark ? Brightness.dark : Brightness.light,
        ),
      ),
      home: Scaffold(
        backgroundColor: isDark ? AppColors.ink : AppColors.mist,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: isDark ? AppColors.cyan : AppColors.blue,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Steam Companion',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: isDark ? AppColors.softWhite : const Color(0xFF151A23),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '正在加载本地账号…',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.slate : AppColors.slateLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
