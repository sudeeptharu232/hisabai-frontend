import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/app.dart';

import '../../support/fake_expense_server.dart';
import '../../support/test_support.dart';

/// Starts the whole app signed in (stored token) and opens the expense list.
Future<void> openExpenses(
  WidgetTester tester,
  FakeExpenseServer server, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final app = TestApp(server.handle, storedToken: FakeExpenseServer.token);
  await tester.pumpWidget(
    HisabAiApp(
      auth: app.auth,
      healthClient: app.healthClient,
      expenseRepository: app.expenseRepository,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-expenses')));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> chooseCategory(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('expense-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  group('list states', () {
    testWidgets('shows a loading indicator, then the empty state', (
      tester,
    ) async {
      final server = FakeExpenseServer()..listGate = Completer<void>();
      await openExpenses(tester, server, settle: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('expenses-loading')), findsOneWidget);

      server.listGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expenses-loading')), findsNothing);
      expect(find.byKey(const Key('expenses-empty')), findsOneWidget);
      expect(find.textContaining('No expenses yet'), findsOneWidget);
    });

    testWidgets('shows an error with Retry, and recovers', (tester) async {
      final server = FakeExpenseServer()..failListTimes = 1;
      server.seed('Himal Traders', 125050);
      await openExpenses(tester, server);

      expect(find.byKey(const Key('expenses-error')), findsOneWidget);

      await tester.tap(find.byKey(const Key('expenses-retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expenses-error')), findsNothing);
      expect(find.text('Himal Traders'), findsOneWidget);
    });

    testWidgets('lists expenses with NPR formatting, date and category', (
      tester,
    ) async {
      final server = FakeExpenseServer();
      server.seed(
        'Himal Traders',
        125050,
        categoryId: 'cat-rent',
        date: '2026-10-01',
      );
      server.seed('Sita Store', 12345678);
      await openExpenses(tester, server);

      expect(find.text('Himal Traders'), findsOneWidget);
      expect(find.text('NPR 1,250.50'), findsOneWidget);
      expect(find.text('2026-10-01 - Rent'), findsOneWidget);
      expect(find.text('NPR 1,23,456.78'), findsOneWidget);
    });

    testWidgets('loads more pages on request', (tester) async {
      final server = FakeExpenseServer();
      for (var i = 1; i <= 25; i++) {
        server.seed('Shop $i', i * 100);
      }
      await openExpenses(tester, server);

      final loadMore = find.byKey(const Key('expenses-load-more'));
      await tester.scrollUntilVisible(
        loadMore,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('Load more (20 of 25)'), findsOneWidget);

      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      expect(
        server.count(
          'GET /api/v1/businesses/${FakeExpenseServer.businessId}/expenses',
        ),
        2,
      );
      expect(find.byKey(const Key('expenses-load-more')), findsNothing);
    });

    testWidgets('searching by supplier filters the list', (tester) async {
      final server = FakeExpenseServer();
      server.seed('Himal Traders', 100);
      server.seed('Sita Store', 200);
      await openExpenses(tester, server);

      await tester.enterText(find.byKey(const Key('expense-search')), 'sita');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Sita Store'), findsOneWidget);
      expect(find.text('Himal Traders'), findsNothing);

      await tester.enterText(find.byKey(const Key('expense-search')), 'zzz');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('No expenses match your search.'), findsOneWidget);
    });
  });

  group('add expense', () {
    testWidgets(
      'shows validation errors and sends nothing when the form is empty',
      (tester) async {
        final server = FakeExpenseServer();
        await openExpenses(tester, server);

        await tester.tap(find.byKey(const Key('add-expense')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('expense-save')));
        await tester.pumpAndSettle();

        expect(find.text('Enter the supplier or shop name'), findsOneWidget);
        expect(find.text('Enter the amount'), findsOneWidget);
        expect(find.text('Choose a category'), findsOneWidget);
        expect(
          server.count(
            'POST /api/v1/businesses/${FakeExpenseServer.businessId}/expenses',
          ),
          0,
        );
      },
    );

    testWidgets('rejects a bad amount on the device', (tester) async {
      final server = FakeExpenseServer();
      await openExpenses(tester, server);
      await tester.tap(find.byKey(const Key('add-expense')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('expense-merchant')),
        'Himal Traders',
      );
      await tester.enterText(find.byKey(const Key('expense-amount')), '12.345');
      await chooseCategory(tester, 'Rent');
      await tester.tap(find.byKey(const Key('expense-save')));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount like 1250.50'), findsOneWidget);
      expect(server.expenses, isEmpty);
    });

    testWidgets(
      'requires the printed date for BS and checks subtotal plus tax',
      (tester) async {
        final server = FakeExpenseServer();
        await openExpenses(tester, server);
        await tester.tap(find.byKey(const Key('add-expense')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('expense-merchant')),
          'Himal Traders',
        );
        await tester.enterText(find.byKey(const Key('expense-amount')), '1500');
        await tester.enterText(
          find.byKey(const Key('expense-subtotal')),
          '1000',
        );
        await tester.enterText(find.byKey(const Key('expense-tax')), '100');
        await chooseCategory(tester, 'Rent');

        await tester.tap(find.byKey(const Key('expense-calendar')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('BS (Bikram Sambat)').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('expense-save')));
        await tester.pumpAndSettle();

        expect(
          find.text('Type the date exactly as printed on the bill'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Subtotal plus tax must equal the total'),
          findsOneWidget,
        );
        expect(server.expenses, isEmpty);
      },
    );

    testWidgets(
      'saves a valid expense in exact paisa and shows it in the list',
      (tester) async {
        final server = FakeExpenseServer();
        await openExpenses(tester, server);

        await tester.tap(find.byKey(const Key('add-expense')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('expense-merchant')),
          'Himal Traders',
        );
        await tester.enterText(
          find.byKey(const Key('expense-amount')),
          '1,250.50',
        );
        await chooseCategory(tester, 'Rent');
        await tester.tap(find.byKey(const Key('expense-save')));
        await tester.pumpAndSettle();

        expect(find.text('Expense saved'), findsOneWidget);
        expect(find.text('Himal Traders'), findsOneWidget);
        expect(find.text('NPR 1,250.50'), findsOneWidget);

        final saved = server.expenses.single;
        expect(saved['amount_paisa'], 125050);
        expect(saved['category_id'], 'cat-rent');
        expect(saved['original_calendar'], 'unknown');
      },
    );

    testWidgets('shows a server-side validation error under the field', (
      tester,
    ) async {
      final server = FakeExpenseServer();
      await openExpenses(tester, server);

      await tester.tap(find.byKey(const Key('add-expense')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('expense-merchant')),
        'REJECT',
      );
      await tester.enterText(find.byKey(const Key('expense-amount')), '10');
      await chooseCategory(tester, 'Other');
      await tester.tap(find.byKey(const Key('expense-save')));
      await tester.pumpAndSettle();

      expect(find.text('The merchant name is not accepted.'), findsOneWidget);
      expect(find.byKey(const Key('expense-save')), findsOneWidget);
      expect(server.expenses, isEmpty);
    });
  });

  group('detail, edit and delete', () {
    testWidgets(
      'shows every field, including the printed BS date and tax breakdown',
      (tester) async {
        final server = FakeExpenseServer();
        server.seed(
          'Himal Traders',
          113000,
          categoryId: 'cat-rent',
          calendar: 'BS',
          printedText: '२०८३/०६/१५',
          subtotal: 100000,
          tax: 13000,
          notes: 'October stock',
        );
        await openExpenses(tester, server);

        await tester.tap(find.text('Himal Traders'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('detail-amount')), findsOneWidget);
        expect(find.text('NPR 1,130.00'), findsOneWidget);
        expect(find.text('NPR 1,000.00'), findsOneWidget);
        expect(find.text('NPR 130.00'), findsOneWidget);
        expect(find.text('२०८३/०६/१५ (BS)'), findsOneWidget);
        expect(find.text('2026-10-01'), findsOneWidget);
        expect(find.text('October stock'), findsOneWidget);
      },
    );

    testWidgets('editing saves changes and the list reflects them', (
      tester,
    ) async {
      final server = FakeExpenseServer();
      server.seed('Himal Traders', 125050, categoryId: 'cat-rent');
      await openExpenses(tester, server);

      await tester.tap(find.text('Himal Traders'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-expense')));
      await tester.pumpAndSettle();

      // The form is pre-filled with the stored values.
      expect(
        find.widgetWithText(TextFormField, 'Himal Traders'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '1250.50'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('expense-merchant')),
        'Himal Wholesale',
      );
      await tester.enterText(find.byKey(const Key('expense-amount')), '2000');
      await tester.tap(find.byKey(const Key('expense-save')));
      await tester.pumpAndSettle();

      expect(find.text('Changes saved'), findsOneWidget);
      expect(find.text('Himal Wholesale'), findsWidgets);
      expect(find.text('NPR 2,000.00'), findsOneWidget);
      expect(server.expenses.single['amount_paisa'], 200000);
      expect(server.expenses.single['category_id'], 'cat-rent');
    });

    testWidgets('delete asks for confirmation; cancel keeps the expense', (
      tester,
    ) async {
      final server = FakeExpenseServer();
      server.seed('Himal Traders', 125050);
      await openExpenses(tester, server);
      await tester.tap(find.text('Himal Traders'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete-expense')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this expense?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('detail-amount')), findsOneWidget);
      expect(server.expenses, hasLength(1));
    });

    testWidgets(
      'confirming delete removes the expense and returns to the list',
      (tester) async {
        final server = FakeExpenseServer();
        server.seed('Himal Traders', 125050);
        await openExpenses(tester, server);
        await tester.tap(find.text('Himal Traders'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('delete-expense')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await tester.pumpAndSettle();

        expect(server.expenses, isEmpty);
        expect(find.text('Expense deleted'), findsOneWidget);
        expect(find.byKey(const Key('expenses-empty')), findsOneWidget);
      },
    );

    testWidgets('a member cannot edit or delete a colleague\'s expense', (
      tester,
    ) async {
      final server = FakeExpenseServer(isOwner: false);
      server.seed('Colleague Shop', 100, createdBy: 99);
      server.seed('My Shop', 200, createdBy: FakeExpenseServer.userId);
      await openExpenses(tester, server);

      await tester.tap(find.text('Colleague Shop'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-expense')), findsNothing);
      expect(find.byKey(const Key('delete-expense')), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Shop'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-expense')), findsOneWidget);
      expect(find.byKey(const Key('delete-expense')), findsOneWidget);
    });
  });
}
