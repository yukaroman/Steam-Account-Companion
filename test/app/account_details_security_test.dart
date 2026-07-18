import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/app/app.dart';
import 'package:steam_account_companion/app/app_services.dart';
import 'package:steam_account_companion/core/security/local_auth_biometric_service.dart';
import 'package:steam_account_companion/features/settings/data/theme_preferences.dart';

/// Unlock page has a repeating pulse animation — avoid pumpAndSettle.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 16]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _unlock(WidgetTester tester) async {
  // AlwaysSucceed biometrics may auto-prompt and unlock before we tap.
  for (var i = 0; i < 30; i++) {
    if (find.byKey(const Key('unlock-button')).evaluate().isEmpty) {
      await _pumpFrames(tester, 8);
      return;
    }
    await tester.pump(const Duration(milliseconds: 40));
  }
  final unlock = find.byKey(const Key('unlock-button'));
  expect(unlock, findsOneWidget);
  await tester.tap(unlock);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await _pumpFrames(tester);
}

Future<void> _scrollDetailsTo(WidgetTester tester, Finder target) async {
  // Account details content lives in a SingleChildScrollView inside the sheet.
  final scrollable = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(Scrollable),
  );
  if (scrollable.evaluate().isEmpty) {
    // Fallback: any scrollable under the sheet body.
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byType(Scrollable).last,
    );
  } else {
    await tester.scrollUntilVisible(target, 120, scrollable: scrollable.last);
  }
  await _pumpFrames(tester, 8);
}

void main() {
  test('loadAccountDetails hides revocation until includeSecrets', () async {
    final services = await AppServices.createInMemory(
      seedDemoAccounts: false,
      syncServerTimeOnStart: false,
    );
    final source = File('test/fixtures/mafile/sample_sanitized.maFile.json')
        .readAsStringSync();
    final imported = await services.importMaFileJson(source);
    expect(imported.successCount, 1);
    final accountId = imported.importedAccountIds.single;

    final hidden = await services.loadAccountDetails(accountId);
    expect(hidden, isNotNull);
    expect(hidden!.hasRevocationCode, isTrue);
    expect(hidden.revocationCode, isNull);
    expect(hidden.secretsRevealed, isFalse);
    expect(hidden.sharedSecretBase64, isNull);
    expect(hidden.identitySecretBase64, isNull);

    final revealed = await services.loadAccountDetails(
      accountId,
      includeSecrets: true,
    );
    expect(revealed, isNotNull);
    expect(revealed!.secretsRevealed, isTrue);
    expect(revealed.revocationCode, 'R12345');
    expect(revealed.sharedSecretBase64, isNotNull);
    expect(revealed.identitySecretBase64, isNotNull);
  });

  testWidgets(
    'lock gate covers and dismisses revealed account details sheet',
    (tester) async {
      // Tall surface so the sheet body has room after scrolling.
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final services = await AppServices.createInMemory(
        seedDemoAccounts: false,
        syncServerTimeOnStart: false,
        biometricService: const AlwaysSucceedBiometricService(),
      );
      final source = File('test/fixtures/mafile/sample_sanitized.maFile.json')
          .readAsStringSync();
      await services.importMaFileJson(source);

      await tester.pumpWidget(
        SteamCompanionApp(
          services: services,
          initialFaceIdEnabled: true,
          initialAutoLock: ThemePreferences.autoLockImmediate,
        ),
      );
      await tester.pump();
      await _pumpFrames(tester);

      await _unlock(tester);

      expect(find.byTooltip('账号信息'), findsOneWidget);
      await tester.tap(find.byTooltip('账号信息'));
      await _pumpFrames(tester, 24);

      expect(find.textContaining('R12345'), findsNothing);

      final reveal = find.text('确认后查看密钥');
      expect(reveal, findsOneWidget);
      await _scrollDetailsTo(tester, reveal);
      await tester.tap(reveal);
      await _pumpFrames(tester, 12);

      expect(find.text('确认查看'), findsOneWidget);
      await tester.tap(find.text('确认查看'));
      await _pumpFrames(tester, 24);

      // Revealed values must be present before lock.
      expect(find.textContaining('R12345'), findsWidgets);
      expect(find.text('shared_secret (Base64)'), findsOneWidget);

      // Unlock grace uses wall-clock DateTime. runAsync escapes fake-async so
      // real time and DateTime.now() advance together.
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(); // post-frame popUntil
      await _pumpFrames(tester);

      expect(find.byKey(const Key('unlock-button')), findsOneWidget);
      // Offstage + popUntil: revealed secrets and sheet actions are gone.
      expect(find.textContaining('R12345'), findsNothing);
      expect(find.text('shared_secret (Base64)'), findsNothing);
      expect(find.text('确认后查看密钥'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('manual lock shows unlock gate above home', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Start without Face ID so unlock is a plain tap; enable gate only via lock.
    // (AlwaysSucceed would auto-reauth immediately after lock.)
    final services = await AppServices.createInMemory(
      seedDemoAccounts: true,
      syncServerTimeOnStart: false,
      biometricService: const UnavailableBiometricService(),
    );

    await tester.pumpWidget(
      SteamCompanionApp(
        services: services,
        initialFaceIdEnabled: false,
      ),
    );
    await tester.pump();
    await _pumpFrames(tester);

    // Already unlocked (Face ID off). Open details so a modal is on the stack.
    await tester.tap(find.byTooltip('账号信息'));
    await _pumpFrames(tester, 24);
    expect(find.text('账号信息'), findsWidgets);

    Navigator.of(tester.element(find.text('确认后查看密钥'))).pop();
    await _pumpFrames(tester, 12);

    await tester.tap(find.text('设置'));
    await _pumpFrames(tester, 16);

    final lock = find.byKey(const Key('settings-lock-button'));
    await tester.scrollUntilVisible(
      lock,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await _pumpFrames(tester, 8);
    await tester.ensureVisible(lock);
    await tester.tap(lock, warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    await _pumpFrames(tester, 20);

    expect(find.byKey(const Key('unlock-button')), findsOneWidget);
    expect(find.text('确认后查看密钥'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
