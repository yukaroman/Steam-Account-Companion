import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/app/app.dart';
import 'package:steam_account_companion/app/app_services.dart';
import 'package:steam_account_companion/core/security/local_auth_biometric_service.dart';

void main() {
  testWidgets('launch skips unlock and opens token home', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SteamCompanionApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // No Face ID / unlock gate on cold start (default unlocked).
    expect(find.text('轻点解锁'), findsNothing);
    expect(find.text('令牌'), findsWidgets);
    // Without AppServices the list is empty — import empty state, not demos.
    expect(find.text('暂无账号'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Face ID gate stays locked when biometrics unavailable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final services = await AppServices.createInMemory(
      seedDemoAccounts: false,
      syncServerTimeOnStart: false,
      biometricService: const UnavailableBiometricService(),
    );

    await tester.pumpWidget(
      SteamCompanionApp(
        services: services,
        initialFaceIdEnabled: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('unlock-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('unlock-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Fail closed: still on unlock page.
    expect(find.byKey(const Key('unlock-button')), findsOneWidget);
    expect(find.textContaining('保持锁定'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Face ID succeeds with system auth service', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final services = await AppServices.createInMemory(
      seedDemoAccounts: false,
      syncServerTimeOnStart: false,
      biometricService: const AlwaysSucceedBiometricService(),
    );

    await tester.pumpWidget(
      SteamCompanionApp(
        services: services,
        initialFaceIdEnabled: true,
      ),
    );
    // Auto-prompt + unlock may complete asynchronously.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byKey(const Key('unlock-button')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('unlock-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('令牌'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
