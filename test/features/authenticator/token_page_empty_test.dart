import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/features/accounts/models/steam_account.dart';
import 'package:steam_account_companion/features/authenticator/data/mock_authenticator_service.dart';
import 'package:steam_account_companion/features/authenticator/presentation/token_page.dart';

void main() {
  testWidgets('empty account list shows empty state without crashing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var importTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TokenPage(
            authenticatorService: MockAuthenticatorService(),
            accounts: const [],
            onImportRequested: () => importTaps += 1,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('暂无账号'), findsOneWidget);
    expect(find.byKey(const Key('token-empty-import')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('token-empty-import')));
    await tester.pump();
    expect(importTaps, 1);
  });

  testWidgets('selected index clamps when accounts shrink', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final accounts = [
      const SteamAccount(
        id: 'a',
        nickname: 'Alpha',
        loginNameHint: 'a••••',
        avatarColor: Color(0xFF112233),
        initials: 'A',
      ),
      const SteamAccount(
        id: 'b',
        nickname: 'Beta',
        loginNameHint: 'b••••',
        avatarColor: Color(0xFF223344),
        initials: 'B',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TokenPage(
            authenticatorService: MockAuthenticatorService(),
            accounts: accounts,
          ),
        ),
      ),
    );
    await tester.pump();

    // Select second account.
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(find.text('Beta'), findsWidgets);

    // Shrink to a single account (as if the other was deleted).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TokenPage(
            authenticatorService: MockAuthenticatorService(),
            accounts: accounts.take(1).toList(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('暂无账号'), findsNothing);
  });

  testWidgets('list becoming empty switches to empty state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TokenPage(
            authenticatorService: MockAuthenticatorService(),
            accounts: const [
              SteamAccount(
                id: 'a',
                nickname: 'Alpha',
                loginNameHint: 'a••••',
                avatarColor: Color(0xFF112233),
                initials: 'A',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Alpha'), findsWidgets);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TokenPage(
            authenticatorService: MockAuthenticatorService(),
            accounts: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('暂无账号'), findsOneWidget);
  });
}
