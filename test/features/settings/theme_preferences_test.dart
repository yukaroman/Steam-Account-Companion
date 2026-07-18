import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:steam_account_companion/app/app_controller.dart';
import 'package:steam_account_companion/features/settings/data/theme_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ThemePreferences round-trips theme mode and OLED', () async {
    final prefs = await ThemePreferences.open();
    expect(prefs.loadThemeMode(), ThemeMode.system);
    expect(prefs.loadOledMode(), isFalse);

    await prefs.saveThemeMode(ThemeMode.dark);
    await prefs.saveOledMode(true);

    final reopened = await ThemePreferences.open();
    expect(reopened.loadThemeMode(), ThemeMode.dark);
    expect(reopened.loadOledMode(), isTrue);

    await reopened.saveThemeMode(ThemeMode.light);
    expect((await ThemePreferences.open()).loadThemeMode(), ThemeMode.light);
  });

  test('AppController persists theme changes via ThemePreferences', () async {
    final prefs = await ThemePreferences.open();
    final controller = AppController(
      themePreferences: prefs,
      themeMode: prefs.loadThemeMode(),
      oledMode: prefs.loadOledMode(),
    );

    await controller.setThemeMode(ThemeMode.light);
    await controller.setOledMode(true);

    final reopened = await ThemePreferences.open();
    expect(reopened.loadThemeMode(), ThemeMode.light);
    expect(reopened.loadOledMode(), isTrue);

    final restored = AppController(
      themePreferences: reopened,
      themeMode: reopened.loadThemeMode(),
      oledMode: reopened.loadOledMode(),
    );
    expect(restored.themeMode, ThemeMode.light);
    expect(restored.oledMode, isTrue);
  });
}
