import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/app.dart';
import 'package:hisabai/core/money/money.dart';
import 'package:hisabai/features/auth/auth_models.dart';
import 'package:hisabai/features/expenses/expense_models.dart';
import 'package:hisabai/features/receipts/receipt_image.dart';
import 'package:hisabai/features/receipts/receipt_repository.dart';
import 'package:hisabai/features/receipts/receipt_scan_screen.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/fake_expense_server.dart';
import '../../support/fake_receipt_server.dart';
import '../../support/test_support.dart';

final _today = DateTime(2026, 10, 28);

const _business = BusinessSummary(
  id: FakeExpenseServer.businessId,
  name: 'Himal Kirana Pasal',
  role: 'owner',
);

const _categories = [
  ExpenseCategory(id: 'cat-inv', name: 'Inventory & supplies', isSystem: true),
  ExpenseCategory(id: 'cat-rent', name: 'Rent', isSystem: true),
  ExpenseCategory(id: 'cat-other', name: 'Other', isSystem: true),
];

/// Opens the scan screen from a plain home screen, so the result of saving
/// (a pop back to the home screen) can be observed.
Future<void> pumpScan(
  WidgetTester tester,
  ReceiptHarness h,
  FakeReceiptImagePicker picker,
) async {
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open-scan'),
              onPressed: () => Navigator.of(context).push<Expense>(
                MaterialPageRoute<Expense>(
                  builder: (_) => ReceiptScanScreen(
                    receiptRepository: h.receipts,
                    expenseRepository: h.expenseRepository,
                    business: _business,
                    categories: _categories,
                    imagePicker: picker,
                    today: _today,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-scan')));
  await tester.pumpAndSettle();
}

Future<void> pickFromGallery(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pick-gallery')));
  await tester.pumpAndSettle();
}

Future<void> tapRead(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('receipt-extract')));
  await tester.pumpAndSettle();
}

/// Scan screen -> pick -> read -> the review screen is showing.
Future<void> openReview(
  WidgetTester tester,
  ReceiptHarness h, {
  FakeReceiptImagePicker? picker,
}) async {
  await pumpScan(
    tester,
    h,
    picker ?? FakeReceiptImagePicker([preparedImage()]),
  );
  await pickFromGallery(tester);
  await tapRead(tester);
  expect(find.text('Review receipt'), findsOneWidget);
}

Future<void> chooseCategory(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('review-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> tapSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-save')));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

void main() {
  group('scan screen', () {
    testWidgets('shows the privacy notice before anything is sent', (
      tester,
    ) async {
      final h = ReceiptHarness();
      await pumpScan(tester, h, FakeReceiptImagePicker([]));

      expect(find.byKey(const Key('receipt-privacy-notice')), findsOneWidget);
      expect(find.textContaining('Gemini'), findsOneWidget);
      expect(find.textContaining('sent to the HisabAI server'), findsOneWidget);
      expect(
        find.textContaining('not read only on your phone'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('receipt-extract')))
            .onPressed,
        isNull,
        reason: 'nothing can be sent without a photo',
      );
      expect(h.calls, isEmpty);
    });

    testWidgets(
      'a chosen photo is previewed and enables reading, but nothing is sent',
      (tester) async {
        final h = ReceiptHarness();
        final picker = FakeReceiptImagePicker([preparedImage()]);
        await pumpScan(tester, h, picker);

        await pickFromGallery(tester);

        expect(picker.calls, [ImageSource.gallery]);
        expect(find.byKey(const Key('receipt-preview')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('receipt-extract')))
              .onPressed,
          isNotNull,
        );
        expect(h.calls, isEmpty);
      },
    );

    testWidgets('the camera button opens the camera', (tester) async {
      final picker = FakeReceiptImagePicker([preparedImage()]);
      await pumpScan(tester, ReceiptHarness(), picker);

      await tester.tap(find.byKey(const Key('pick-camera')));
      await tester.pumpAndSettle();

      expect(picker.calls, [ImageSource.camera]);
    });

    testWidgets('cancelling leaves the screen as it was', (tester) async {
      final h = ReceiptHarness();
      await pumpScan(tester, h, FakeReceiptImagePicker([null]));

      await pickFromGallery(tester);

      expect(find.byKey(const Key('receipt-preview')), findsNothing);
      expect(find.byKey(const Key('receipt-error')), findsNothing);
      expect(h.calls, isEmpty);
    });

    testWidgets('a picker or image error is shown', (tester) async {
      final picker = FakeReceiptImagePicker([
        const ReceiptImageException(
          'Camera access was denied. Choose from the gallery.',
        ),
      ]);
      await pumpScan(tester, ReceiptHarness(), picker);

      await tester.tap(find.byKey(const Key('pick-camera')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt-error')), findsOneWidget);
      expect(find.textContaining('Camera access was denied'), findsOneWidget);
      expect(find.byKey(const Key('receipt-preview')), findsNothing);
    });

    testWidgets('reading opens the review and saves nothing', (tester) async {
      final h = ReceiptHarness();
      await openReview(tester, h);

      expect(h.extractCalls, 1);
      expect(h.createCalls, 0);
      expect(h.expenses.expenses, isEmpty);
    });

    testWidgets(
      'offline: explains, keeps the photo, and a retry works without picking again',
      (tester) async {
        final h = ReceiptHarness()
          ..failure = const SocketException('unreachable');
        final picker = FakeReceiptImagePicker([preparedImage()]);
        await pumpScan(tester, h, picker);
        await pickFromGallery(tester);

        await tapRead(tester);

        expect(find.textContaining('internet connection'), findsOneWidget);
        expect(find.byKey(const Key('receipt-preview')), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Review receipt'), findsNothing);

        h.failure = null;
        await tapRead(tester);

        expect(find.text('Review receipt'), findsOneWidget);
        expect(h.extractCalls, 2);
        expect(picker.calls, hasLength(1));
        expect(h.createCalls, 0);
      },
    );

    testWidgets('a double tap on "Read receipt" sends one request', (
      tester,
    ) async {
      final h = ReceiptHarness()..extractGate = Completer<void>();
      await pumpScan(tester, h, FakeReceiptImagePicker([preparedImage()]));
      await pickFromGallery(tester);

      await tester.tap(find.byKey(const Key('receipt-extract')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('receipt-extract')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(h.extractCalls, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('receipt-extract')))
            .onPressed,
        isNull,
        reason: 'disabled while reading',
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('pick-gallery')))
            .onPressed,
        isNull,
      );

      h.extractGate!.complete();
      await tester.pumpAndSettle();
      expect(h.extractCalls, 1);
      expect(find.text('Review receipt'), findsOneWidget);
    });

    testWidgets(
      'the daily allowance, an expired session and a server error get their own text',
      (tester) async {
        final h = ReceiptHarness();
        await pumpScan(tester, h, FakeReceiptImagePicker([preparedImage()]));
        await pickFromGallery(tester);

        h
          ..status = 429
          ..body = {'message': 'x', 'code': 'business_quota_exceeded'};
        await tapRead(tester);
        expect(find.textContaining('allowance for today'), findsOneWidget);

        h
          ..status = 401
          ..body = {'message': 'Unauthenticated.'};
        await tapRead(tester);
        expect(find.textContaining('sign in again'), findsOneWidget);

        h
          ..status = 500
          ..body = {'message': 'SQLSTATE secret internals'};
        await tapRead(tester);
        expect(find.textContaining('server had a problem'), findsOneWidget);
        expect(find.textContaining('SQLSTATE'), findsNothing);
        expect(find.byKey(const Key('receipt-preview')), findsOneWidget);
      },
    );
  });

  group('review screen: what is shown', () {
    testWidgets('shows the warnings and the omitted values from the server', (
      tester,
    ) async {
      final h = ReceiptHarness()..body = bsExtractionBody();
      await openReview(tester, h);

      expect(find.byKey(const Key('review-warnings')), findsOneWidget);
      expect(
        find.text('The date is printed in the BS calendar.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('review-omitted')), findsOneWidget);
      expect(
        find.text(
          'Date: A BS date is never converted. Choose the AD date yourself.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'printed amounts stay as read and the suggested subtotal is explained',
      (tester) async {
        final h = ReceiptHarness();
        await openReview(tester, h);

        expect(_text(tester, 'printed-subtotal'), contains('2,860.00'));
        expect(_text(tester, 'printed-subtotal'), contains('NPR 2,860.00'));
        expect(_text(tester, 'printed-discount'), contains('60.00'));
        expect(_text(tester, 'printed-tax'), contains('364.00'));
        expect(_text(tester, 'printed-total'), contains('3,164.00'));
        expect(_text(tester, 'printed-supplier'), 'Himal Traders');

        // The editable subtotal is the SUGGESTED one (after the discount), not the printed one.
        expect(_fieldText(tester, 'review-subtotal'), paisaToInputText(280000));
        expect(
          _fieldText(tester, 'review-subtotal'),
          isNot(paisaToInputText(286000)),
        );
        expect(_fieldText(tester, 'review-tax'), paisaToInputText(36400));
        expect(_fieldText(tester, 'review-amount'), paisaToInputText(316400));

        final note = _noteText(tester);
        expect(note, contains('NPR 2,800.00'));
        expect(note, contains('NPR 2,860.00'));
        expect(note, contains('NPR 60.00'));
        expect(note, contains('printed amounts above are unchanged'));
      },
    );

    testWidgets('without a discount adjustment there is no discount note', (
      tester,
    ) async {
      final h = ReceiptHarness()
        ..body = extractionBody(
          prefill: {
            'merchant_name': 'Himal Traders',
            'amount_paisa': 323180,
            'subtotal_paisa': 286000,
            'tax_paisa': 37180,
            'expense_date': '2026-10-27',
            'original_date_text': '2026-10-27',
            'original_calendar': 'AD',
          },
          warnings: <Object?>[],
        );
      await openReview(tester, h);

      expect(find.byKey(const Key('discount-adjusted-note')), findsNothing);
      expect(find.byKey(const Key('review-warnings')), findsNothing);
      expect(_fieldText(tester, 'review-subtotal'), paisaToInputText(286000));
    });

    testWidgets(
      'a sparse response opens fine and shows "Not read", never invented values',
      (tester) async {
        final h = ReceiptHarness()..body = sparseExtractionBody();
        await openReview(tester, h);

        expect(find.text('Not read'), findsWidgets);
        expect(_fieldText(tester, 'review-merchant'), '');
        expect(_fieldText(tester, 'review-amount'), paisaToInputText(5000));
        expect(_fieldText(tester, 'review-subtotal'), '');
        expect(_text(tester, 'review-date-value'), 'Not set');
        expect(find.byKey(const Key('review-warnings')), findsNothing);
        expect(find.byKey(const Key('review-omitted')), findsNothing);

        await tapSave(tester);
        expect(h.createCalls, 0, reason: 'required fields are missing');
      },
    );

    testWidgets('a receipt that is not in NPR says so', (tester) async {
      final receipt = receiptJson();
      (receipt['currency']! as Map<String, Object?>)['supported'] = false;
      final h = ReceiptHarness()..body = extractionBody(receipt: receipt);
      await openReview(tester, h);

      expect(find.byKey(const Key('review-currency-note')), findsOneWidget);
    });
  });

  group('review screen: dates', () {
    testWidgets(
      'a BS date leaves the date empty (never today) and keeps what was printed',
      (tester) async {
        final h = ReceiptHarness()..body = bsExtractionBody();
        await openReview(tester, h);

        expect(_text(tester, 'review-date-value'), 'Not set');
        expect(
          find.text('2026-10-28'),
          findsNothing,
          reason: 'today is not filled in',
        );
        expect(find.text('BS (Bikram Sambat)'), findsWidgets);
        expect(_fieldText(tester, 'review-printed-date'), '2083/06/30');
        expect(find.textContaining('never converted'), findsWidgets);
      },
    );

    testWidgets(
      'saving is blocked until the AD date is chosen, then it is saved as chosen',
      (tester) async {
        final h = ReceiptHarness()..body = bsExtractionBody();
        await openReview(tester, h);
        await chooseCategory(tester, 'Inventory & supplies');

        await tapSave(tester);

        expect(find.text('Choose the date'), findsOneWidget);
        expect(h.createCalls, 0);

        await tester.tap(find.byKey(const Key('review-date')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(_text(tester, 'review-date-value'), '2026-10-28');

        await tapSave(tester);

        expect(h.createCalls, 1);
        final body = h.createBodies.single;
        expect(body['expense_date'], '2026-10-28');
        expect(body['original_calendar'], 'BS');
        expect(body['original_date_text'], '2083/06/30');
      },
    );

    testWidgets(
      'a confirmed AD date is prefilled and saved with its calendar',
      (tester) async {
        final h = ReceiptHarness();
        await openReview(tester, h);
        await chooseCategory(tester, 'Inventory & supplies');

        expect(_text(tester, 'review-date-value'), '2026-10-27');
        await tapSave(tester);

        final body = h.createBodies.single;
        expect(body['expense_date'], '2026-10-27');
        expect(body['original_calendar'], 'AD');
        expect(body['original_date_text'], '2026-10-27');
      },
    );
  });

  group('review screen: saving', () {
    testWidgets(
      'nothing is saved until the person confirms, and a category is required',
      (tester) async {
        final h = ReceiptHarness();
        await openReview(tester, h);

        expect(h.createCalls, 0);

        await tapSave(tester);
        expect(h.createCalls, 0, reason: 'no category chosen yet');

        await chooseCategory(tester, 'Rent');
        expect(h.createCalls, 0, reason: 'choosing a category does not save');

        await tapSave(tester);
        expect(h.createCalls, 1);
      },
    );

    testWidgets(
      'saves exactly what is shown: the suggested subtotal, and no line items',
      (tester) async {
        final h = ReceiptHarness();
        await openReview(tester, h);
        await chooseCategory(tester, 'Inventory & supplies');

        await tapSave(tester);

        final body = h.createBodies.single;
        expect(body['merchant_name'], 'Himal Traders');
        expect(body['amount_paisa'], 316400);
        expect(body['subtotal_paisa'], 280000);
        expect(body['tax_paisa'], 36400);
        expect(body['category_id'], 'cat-inv');
        expect(body.containsKey('line_items'), isFalse);
        expect(body.keys, isNot(contains('discount_paisa')));

        expect(h.expenses.expenses, hasLength(1));
        expect(
          find.byKey(const Key('open-scan')),
          findsOneWidget,
          reason: 'back at the start',
        );
      },
    );

    testWidgets('edited values are what gets saved', (tester) async {
      final h = ReceiptHarness();
      await openReview(tester, h);
      await chooseCategory(tester, 'Other');

      await tester.enterText(
        find.byKey(const Key('review-merchant')),
        'Edited Shop',
      );
      await tester.enterText(find.byKey(const Key('review-amount')), '3200');
      await tester.enterText(find.byKey(const Key('review-subtotal')), '');
      await tester.enterText(find.byKey(const Key('review-tax')), '');
      await tester.enterText(
        find.byKey(const Key('review-notes')),
        'checked by me',
      );
      await tapSave(tester);

      final body = h.createBodies.single;
      expect(body['merchant_name'], 'Edited Shop');
      expect(body['amount_paisa'], 320000);
      expect(body['subtotal_paisa'], isNull);
      expect(body['tax_paisa'], isNull);
      expect(body['notes'], 'checked by me');
      expect(body['category_id'], 'cat-other');
    });

    testWidgets(
      'amounts that do not add up are caught before anything is sent',
      (tester) async {
        final h = ReceiptHarness();
        await openReview(tester, h);
        await chooseCategory(tester, 'Other');

        await tester.enterText(find.byKey(const Key('review-tax')), '1000');
        await tapSave(tester);

        expect(h.createCalls, 0);
        expect(
          find.textContaining('Subtotal plus tax must equal the total'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a failed save keeps every edit and can be retried', (
      tester,
    ) async {
      final h = ReceiptHarness();
      await openReview(tester, h);
      await chooseCategory(tester, 'Inventory & supplies');
      await tester.enterText(
        find.byKey(const Key('review-merchant')),
        'REJECT',
      );
      await tester.enterText(find.byKey(const Key('review-notes')), 'keep me');
      await tester.enterText(
        find.byKey(const Key('item-description-0')),
        'Edited item',
      );

      await tapSave(tester);

      expect(h.createCalls, 1);
      expect(find.text('The merchant name is not accepted.'), findsOneWidget);
      expect(
        find.text('Review receipt'),
        findsOneWidget,
        reason: 'still on the review',
      );
      expect(_fieldText(tester, 'review-merchant'), 'REJECT');
      expect(_fieldText(tester, 'review-notes'), 'keep me');
      expect(_fieldText(tester, 'review-amount'), paisaToInputText(316400));
      expect(find.text('Edited item'), findsOneWidget);
      expect(h.expenses.expenses, isEmpty);
      expect(h.extractCalls, 1, reason: 'no new extraction was needed');

      await tester.enterText(
        find.byKey(const Key('review-merchant')),
        'Fixed Shop',
      );
      await tapSave(tester);

      expect(h.createCalls, 2);
      expect(h.expenses.expenses, hasLength(1));
      expect(h.createBodies.last['merchant_name'], 'Fixed Shop');
      expect(h.createBodies.last['notes'], 'keep me');
      expect(h.extractCalls, 1);
    });

    testWidgets(
      'a server error or lost connection while saving keeps the form and can be retried',
      (tester) async {
        final h = ReceiptHarness();
        await openReview(tester, h);
        await chooseCategory(tester, 'Inventory & supplies');
        await tester.enterText(
          find.byKey(const Key('review-notes')),
          'still here',
        );

        h.createStatus = 500;
        await tapSave(tester);

        expect(find.byKey(const Key('review-error')), findsOneWidget);
        expect(find.textContaining('server had a problem'), findsOneWidget);
        expect(find.textContaining('Something internal broke'), findsNothing);
        expect(_fieldText(tester, 'review-notes'), 'still here');
        expect(find.text('Review receipt'), findsOneWidget);
        expect(h.expenses.expenses, isEmpty);

        h
          ..createStatus = null
          ..createFailure = const SocketException('unreachable');
        await tapSave(tester);

        expect(find.textContaining('Cannot reach the server'), findsOneWidget);
        expect(_fieldText(tester, 'review-notes'), 'still here');
        expect(h.expenses.expenses, isEmpty);

        h.createFailure = null;
        await tapSave(tester);

        expect(h.createCalls, 3);
        expect(h.expenses.expenses, hasLength(1));
        expect(h.createBodies.last['notes'], 'still here');
        expect(h.extractCalls, 1, reason: 'the receipt was read only once');
      },
    );

    testWidgets('tapping save twice creates one expense', (tester) async {
      final h = ReceiptHarness();
      await openReview(tester, h);
      await chooseCategory(tester, 'Inventory & supplies');
      h.createGate = Completer<void>();

      await tester.tap(find.byKey(const Key('review-save')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('review-save')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(h.createCalls, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('review-save')))
            .onPressed,
        isNull,
      );

      h.createGate!.complete();
      await tester.pumpAndSettle();

      expect(h.createCalls, 1);
      expect(h.expenses.expenses, hasLength(1));
    });
  });

  group('review screen: line items (review only)', () {
    testWidgets(
      'can be edited, added and removed, with a calculated total and no saving',
      (tester) async {
        final h = ReceiptHarness();
        await openReview(tester, h);

        expect(find.textContaining('does not save them'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('item-description-0')))
              .controller!
              .text,
          'Rice 5kg',
        );
        expect(_text(tester, 'line-items-total'), contains('NPR 2,860.00'));
        expect(find.byKey(const Key('line-items-difference')), findsNothing);

        await tester.enterText(
          find.byKey(const Key('item-line-total-0')),
          '2600',
        );
        await tester.pump();
        expect(_text(tester, 'line-items-total'), contains('NPR 2,960.00'));
        expect(_text(tester, 'line-items-difference'), contains('NPR 100.00'));
        expect(
          _text(tester, 'printed-subtotal'),
          contains('2,860.00'),
          reason: 'printed amount is not replaced',
        );
        expect(
          _fieldText(tester, 'review-subtotal'),
          paisaToInputText(280000),
          reason: 'the expense is not changed either',
        );

        await tester.tap(find.byKey(const Key('add-line-item')));
        await tester.pump();
        expect(find.byKey(const Key('item-description-2')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('item-description-2')),
          'Salt',
        );
        await tester.enterText(
          find.byKey(const Key('item-line-total-2')),
          '40',
        );
        await tester.pump();
        expect(_text(tester, 'line-items-total'), contains('NPR 3,000.00'));

        await tester.tap(find.byKey(const Key('remove-item-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('item-description-1')), findsNothing);
        expect(_text(tester, 'line-items-total'), contains('NPR 2,640.00'));

        expect(h.createCalls, 0);
      },
    );

    testWidgets(
      'an unreadable amount is flagged but never blocks saving the expense',
      (tester) async {
        final h = ReceiptHarness();
        await openReview(tester, h);
        await chooseCategory(tester, 'Inventory & supplies');

        await tester.enterText(
          find.byKey(const Key('item-line-total-0')),
          'abc',
        );
        await tester.pump();
        await tapSave(tester);

        expect(h.createCalls, 1);
      },
    );

    testWidgets('a receipt with no items starts with none and can add one', (
      tester,
    ) async {
      final h = ReceiptHarness()
        ..body = extractionBody(receipt: receiptJson(lineItems: <Object?>[]));
      await openReview(tester, h);

      expect(find.text('No items were read from the receipt.'), findsOneWidget);
      expect(find.byKey(const Key('line-items-total')), findsNothing);

      await tester.tap(find.byKey(const Key('add-line-item')));
      await tester.pump();

      expect(find.byKey(const Key('item-description-0')), findsOneWidget);
    });
  });

  group('entry point', () {
    Future<void> openList(
      WidgetTester tester, {
      required bool withReceipts,
    }) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final server = FakeExpenseServer();
      final app = TestApp(server.handle, storedToken: FakeExpenseServer.token);
      await tester.pumpWidget(
        HisabAiApp(
          auth: app.auth,
          healthClient: app.healthClient,
          expenseRepository: app.expenseRepository,
          receiptRepository: withReceipts
              ? ReceiptRepository(api: app.api)
              : null,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-expenses')));
      await tester.pumpAndSettle();
    }

    testWidgets('the scan button is shown when receipt scanning is wired in', (
      tester,
    ) async {
      await openList(tester, withReceipts: true);

      expect(find.byKey(const Key('scan-receipt')), findsOneWidget);
      expect(find.byKey(const Key('add-expense')), findsOneWidget);

      await tester.tap(find.byKey(const Key('scan-receipt')));
      await tester.pumpAndSettle();

      expect(find.text('Scan receipt'), findsWidgets);
      expect(find.byKey(const Key('receipt-privacy-notice')), findsOneWidget);
    });

    testWidgets('without receipt scanning the screen is exactly as before', (
      tester,
    ) async {
      await openList(tester, withReceipts: false);

      expect(find.byKey(const Key('scan-receipt')), findsNothing);
      expect(find.byKey(const Key('add-expense')), findsOneWidget);
    });
  });
}

String _noteText(WidgetTester tester) {
  final card = find.byKey(const Key('discount-adjusted-note'));
  expect(card, findsOneWidget);
  final text = find.descendant(of: card, matching: find.byType(Text));
  return tester.widget<Text>(text).data ?? '';
}
