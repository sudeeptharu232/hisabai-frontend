import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/app.dart';

import '../../support/fake_server.dart';
import '../../support/test_support.dart';

Future<void> pumpApp(
  WidgetTester tester,
  FakeServer server, {
  String? storedToken,
}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final app = TestApp(server.handle, storedToken: storedToken);
  addTearDown(() => app.tokenStore.clear());
  appUnderTest = app;
  await tester.pumpWidget(
    HisabAiApp(
      auth: app.auth,
      healthClient: app.healthClient,
      expenseRepository: app.expenseRepository,
    ),
  );
  await tester.pumpAndSettle();
}

TestApp? appUnderTest;

Future<void> signIn(WidgetTester tester, {String password = 'correct-pass-1'}) async {
  await tester.enterText(find.byKey(const Key('login-email')), 'sita@example.com');
  await tester.enterText(find.byKey(const Key('login-password')), password);
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

void main() {
  group('start-up', () {
    testWidgets('shows the login screen when nobody is signed in', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);

      expect(find.byKey(const Key('login-submit')), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('goes straight to home when a stored token is still valid', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server, storedToken: FakeServer.token);

      expect(find.text('Sita Sharma'), findsOneWidget);
      expect(find.byKey(const Key('login-submit')), findsNothing);
    });

    testWidgets('falls back to login when the stored token was revoked', (tester) async {
      final server = FakeServer()..tokenValid = false;
      await pumpApp(tester, server, storedToken: FakeServer.token);

      expect(find.byKey(const Key('login-submit')), findsOneWidget);
    });

    testWidgets('offers a retry when the server is unreachable at start', (tester) async {
      final server = FakeServer()..offline = true;
      await pumpApp(tester, server, storedToken: FakeServer.token);

      expect(find.text('Cannot verify your sign-in'), findsOneWidget);

      server.offline = false;
      await tester.tap(find.byKey(const Key('restore-retry')));
      await tester.pumpAndSettle();

      expect(find.text('Sita Sharma'), findsOneWidget);
    });
  });

  group('login', () {
    testWidgets('validates empty fields without calling the server', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);

      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('shows the server error for wrong credentials', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);

      await signIn(tester, password: 'wrong-password');

      expect(find.text('These credentials do not match our records.'), findsOneWidget);
      expect(find.byKey(const Key('login-submit')), findsOneWidget);
    });

    testWidgets('shows a network error when the server is down', (tester) async {
      final server = FakeServer()..offline = true;
      await pumpApp(tester, server);

      await signIn(tester);

      expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    });

    testWidgets('keeps the existing connectivity check reachable', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);

      await tester.tap(find.byKey(const Key('check-connection')));
      await tester.pumpAndSettle();

      expect(find.text('API is reachable'), findsOneWidget);
    });
  });

  group('registration', () {
    Future<void> openRegister(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('go-register')));
      await tester.pumpAndSettle();
    }

    testWidgets('validates fields on the device first', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);
      await openRegister(tester);

      await tester.enterText(find.byKey(const Key('register-password')), 'short');
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('shows a duplicate-email error from the server under the field', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);
      await openRegister(tester);

      await tester.enterText(find.byKey(const Key('register-name')), 'Sita');
      await tester.enterText(find.byKey(const Key('register-email')), server.takenEmail);
      await tester.enterText(find.byKey(const Key('register-password')), 'long-enough-1');
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      expect(find.text('The email has already been taken.'), findsOneWidget);
      expect(find.byKey(const Key('register-submit')), findsOneWidget);
    });

    testWidgets('registers, signs in, and lands on home', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);
      await openRegister(tester);

      await tester.enterText(find.byKey(const Key('register-name')), 'Sita Sharma');
      await tester.enterText(find.byKey(const Key('register-email')), 'sita@example.com');
      await tester.enterText(find.byKey(const Key('register-password')), 'long-enough-1');
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Sita Sharma'), findsOneWidget);
      expect(server.count('GET /api/v1/me'), 1);
    });
  });

  group('signed in', () {
    testWidgets('full flow: sign in, create business, invite, verify, sign out', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);

      await signIn(tester);
      expect(find.text('Set up your business'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('business-name')), 'Himal Kirana Pasal');
      await tester.tap(find.byKey(const Key('business-create')));
      await tester.pumpAndSettle();
      expect(find.text('Himal Kirana Pasal'), findsOneWidget);
      expect(find.text('Your role: Owner'), findsOneWidget);

      await tester.tap(find.byKey(const Key('create-invitation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invitation-code-text')), findsOneWidget);
      expect(find.text('hbinv_FAKECODE1234567890'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      final before = server.count('GET /api/v1/me');
      await tester.tap(find.byKey(const Key('refresh')));
      await tester.pumpAndSettle();
      expect(server.count('GET /api/v1/me'), before + 1);

      await tester.tap(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-submit')), findsOneWidget);
      expect(server.count('POST /api/v1/auth/logout'), 1);
      expect(await appUnderTest!.tokenStore.read(), isNull);
    });

    testWidgets('joining with a wrong code shows the server error', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);
      await signIn(tester);

      await tester.enterText(find.byKey(const Key('invitation-code')), 'hbinv_wrong');
      await tester.tap(find.byKey(const Key('business-join')));
      await tester.pumpAndSettle();

      expect(find.text('This invitation code is invalid or has expired.'), findsOneWidget);
      expect(find.text('Set up your business'), findsOneWidget);
    });

    testWidgets('joining with a valid code shows a member without invite rights', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);
      await signIn(tester);

      await tester.enterText(find.byKey(const Key('invitation-code')), 'hbinv_goodcode');
      await tester.tap(find.byKey(const Key('business-join')));
      await tester.pumpAndSettle();

      expect(find.text('Joined Shop'), findsOneWidget);
      expect(find.text('Your role: Member'), findsOneWidget);
      expect(find.byKey(const Key('create-invitation')), findsNothing);
    });

    testWidgets('a revoked token during use returns the user to login', (tester) async {
      final server = FakeServer();
      await pumpApp(tester, server);
      await signIn(tester);

      server.tokenValid = false; // e.g. revoked from another device
      await tester.tap(find.byKey(const Key('refresh')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-submit')), findsOneWidget);
      expect(await appUnderTest!.tokenStore.read(), isNull);
    });
  });
}
