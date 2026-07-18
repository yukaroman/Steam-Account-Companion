import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/app/app_controller.dart';
import 'package:steam_account_companion/app/app_services.dart';
import 'package:steam_account_companion/features/settings/data/theme_preferences.dart';

void main() {
  test('defaults skip unlock until Face ID or manual lock', () async {
    final controller = AppController();

    expect(controller.themeMode, ThemeMode.system);
    expect(controller.oledMode, isFalse);
    expect(controller.faceIdEnabled, isFalse);
    expect(controller.unlocked, isTrue);
    expect(controller.encryptAccountsAtRest, isTrue);

    await controller.setThemeMode(ThemeMode.light);
    await controller.setOledMode(true);

    expect(controller.themeMode, ThemeMode.light);
    expect(controller.oledMode, isTrue);

    controller.lock();
    expect(controller.unlocked, isFalse);
    controller.unlock();
    expect(controller.unlocked, isTrue);
  });

  test('Face ID enabled starts locked; disabling unlocks', () async {
    final locked = AppController(faceIdEnabled: true);
    expect(locked.unlocked, isFalse);
    locked.unlock();
    expect(locked.unlocked, isTrue);

    await locked.setFaceIdEnabled(false);
    expect(locked.faceIdEnabled, isFalse);
    expect(locked.unlocked, isTrue);

    final unlocked = AppController(faceIdEnabled: false);
    await unlocked.setFaceIdEnabled(true);
    // Enabling mid-session does not force lock until next launch / auto-lock.
    expect(unlocked.faceIdEnabled, isTrue);
    expect(unlocked.unlocked, isTrue);
  });

  test('inactive does not lock (avoids CC thrash and black cover)', () {
    final controller = AppController(
      faceIdEnabled: true,
      autoLock: ThemePreferences.autoLockImmediate,
    );
    controller.unlock();
    controller.debugClearUnlockGrace();
    controller.handleAppLifecycle(AppLifecycleState.inactive);
    expect(controller.unlocked, isTrue);
  });

  test('paused with immediate auto-lock locks once', () {
    final controller = AppController(
      faceIdEnabled: true,
      autoLock: ThemePreferences.autoLockImmediate,
    );
    controller.unlock();
    controller.debugClearUnlockGrace();
    controller.handleAppLifecycle(AppLifecycleState.paused);
    expect(controller.unlocked, isFalse);
  });

  test('resume after unlock grace does not re-lock', () {
    final controller = AppController(
      faceIdEnabled: true,
      autoLock: ThemePreferences.autoLockImmediate,
    );
    controller.unlock();
    // Keep grace — spurious lifecycle after unlock (common on iOS).
    controller.handleAppLifecycle(AppLifecycleState.inactive);
    controller.handleAppLifecycle(AppLifecycleState.paused);
    controller.handleAppLifecycle(AppLifecycleState.resumed);
    expect(controller.unlocked, isTrue);
  });

  test('auto-lock never keeps unlocked across real background', () {
    final controller = AppController(
      faceIdEnabled: true,
      autoLock: ThemePreferences.autoLockNever,
    );
    controller.unlock();
    controller.debugClearUnlockGrace();
    controller.handleAppLifecycle(AppLifecycleState.paused);
    controller.handleAppLifecycle(AppLifecycleState.resumed);
    expect(controller.unlocked, isTrue);
  });

  test('default auto-lock is longest timed option (24 hours)', () {
    final controller = AppController(faceIdEnabled: true);
    expect(controller.autoLock, ThemePreferences.autoLockTwentyFourHours);
    expect(
      ThemePreferences.autoLockDuration(controller.autoLock),
      const Duration(hours: 24),
    );

    controller.unlock();
    controller.debugClearUnlockGrace();
    controller.handleAppLifecycle(AppLifecycleState.paused);
    controller.handleAppLifecycle(AppLifecycleState.resumed);
    expect(controller.unlocked, isTrue);
  });

  test('resume after long pause locks and shows unlock', () {
    final controller = AppController(
      faceIdEnabled: true,
      autoLock: ThemePreferences.autoLockOneMinute,
    );
    controller.unlock();
    controller.debugClearUnlockGrace();
    controller.debugSetPausedAt(
      DateTime.now().subtract(const Duration(minutes: 5)),
    );
    controller.handleAppLifecycle(AppLifecycleState.resumed);
    expect(controller.unlocked, isFalse);
  });

  test('encrypt-at-rest defaults on and can be turned off via services',
      () async {
    final services = await AppServices.createInMemory(seedDemoAccounts: true);
    final controller = AppController(services: services);
    controller.bindServices(services);

    expect(controller.encryptAccountsAtRest, isTrue);
    expect(services.encryptAccountsAtRest, isTrue);

    await controller.setEncryptAccountsAtRest(false);
    expect(controller.encryptAccountsAtRest, isFalse);
    expect(services.encryptAccountsAtRest, isFalse);

    await controller.setEncryptAccountsAtRest(true);
    expect(controller.encryptAccountsAtRest, isTrue);
  });
}
