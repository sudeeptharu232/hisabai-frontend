import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/api/api_exception.dart';
import 'package:hisabai/features/expenses/expense_models.dart';
import 'package:hisabai/features/receipts/receipt_models.dart';

import '../../support/fake_receipt_server.dart';

void main() {
  group('a full response', () {
    final extraction = ReceiptExtraction.fromResponse(extractionBody());

    test('parses the prefill', () {
      final p = extraction.prefill;
      expect(p.merchantName, 'Himal Traders');
      expect(p.amountPaisa, 316400);
      expect(p.subtotalPaisa, 280000);
      expect(p.taxPaisa, 36400);
      expect(p.expenseDate, DateTime(2026, 10, 27));
      expect(p.originalDateText, '2026-10-27');
      expect(p.originalCalendar, PrintedCalendar.ad);
    });

    test('keeps the PRINTED amounts apart from the prefill', () {
      expect(extraction.printedSubtotal.paisa, 286000);
      expect(extraction.printedSubtotal.text, '2,860.00');
      expect(extraction.printedDiscount.paisa, 6000);
      expect(extraction.printedTax.paisa, 36400);
      expect(extraction.printedTotal.paisa, 316400);
      expect(
        extraction.prefill.subtotalPaisa,
        isNot(extraction.printedSubtotal.paisa),
      );
    });

    test('parses line items, warnings and the discount flag', () {
      expect(extraction.lineItems, hasLength(2));
      expect(extraction.lineItems[0].description, 'Rice 5kg');
      expect(extraction.lineItems[0].quantityText, '2');
      expect(extraction.lineItems[0].unitPrice.paisa, 125000);
      expect(extraction.lineItems[1].lineTotal.paisa, 36000);
      expect(extraction.warnings.single.code, 'subtotal_adjusted_for_discount');
      expect(extraction.subtotalAdjustedForDiscount, isTrue);
      expect(extraction.hasWarning('nope'), isFalse);
      expect(extraction.supplierName, 'Himal Traders');
      expect(extraction.currencySupported, isTrue);
      expect(extraction.cached, isFalse);
    });
  });

  group('dates and calendars', () {
    test(
      'a BS receipt has no AD date and keeps the printed text and calendar',
      () {
        final e = ReceiptExtraction.fromResponse(bsExtractionBody());

        expect(e.prefill.expenseDate, isNull);
        expect(e.prefill.originalCalendar, PrintedCalendar.bs);
        expect(e.prefill.originalDateText, '2083/06/30');
        expect(e.printedCalendar, PrintedCalendar.bs);
        expect(e.omitted.single.field, 'expense_date');
        expect(e.hasWarning('date_bs_needs_confirmation'), isTrue);
      },
    );

    test('an unknown calendar value becomes "unknown", never AD', () {
      final e = ReceiptExtraction.fromResponse({
        'data': {
          'prefill': {'original_calendar': 'Gregorian?'},
        },
      });
      expect(e.prefill.originalCalendar, PrintedCalendar.unknown);
    });

    test('only a plain YYYY-MM-DD date is trusted', () {
      for (final bad in [
        '10/27/2026',
        '2026-13-45',
        '2026-1-5',
        '',
        'today',
        '2026-10-27T00:00:00',
      ]) {
        final e = ReceiptExtraction.fromResponse({
          'data': {
            'prefill': {'expense_date': bad},
          },
        });
        expect(e.prefill.expenseDate, isNull, reason: bad);
      }
    });
  });

  group('missing and odd parts', () {
    test(
      'a response with only a prefill still parses; the rest is "not read"',
      () {
        final e = ReceiptExtraction.fromResponse(sparseExtractionBody());

        expect(e.prefill.amountPaisa, 5000);
        expect(e.prefill.merchantName, isNull);
        expect(e.prefill.expenseDate, isNull);
        expect(e.lineItems, isEmpty);
        expect(e.warnings, isEmpty);
        expect(e.omitted, isEmpty);
        expect(e.printedSubtotal.isEmpty, isTrue);
        expect(e.printedTotal.paisa, isNull);
        expect(e.supplierName, isNull);
        expect(e.currencySupported, isNull);
      },
    );

    test('an empty data object parses to an empty extraction', () {
      final e = ReceiptExtraction.fromResponse({'data': <String, Object?>{}});
      expect(e.prefill.amountPaisa, isNull);
      expect(e.lineItems, isEmpty);
    });

    test('no data object is a malformed response', () {
      expect(
        () => ReceiptExtraction.fromResponse(<String, dynamic>{}),
        throwsA(isA<UnexpectedResponseException>()),
      );
      expect(
        () => ReceiptExtraction.fromResponse({'data': 'oops'}),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });

    test('wrongly typed optional values become null instead of crashing', () {
      final e = ReceiptExtraction.fromResponse({
        'data': {
          'prefill': 'oops',
          'prefill_omitted': <String, Object?>{},
          'warnings': [
            7,
            'x',
            {'code': 5},
          ],
          'receipt': {
            'line_items': [
              1,
              'x',
              {'description': 5, 'quantity': 'two'},
            ],
            'printed': {
              'subtotal': {'text': 12, 'paisa': 'x'},
              'tax': 'nope',
            },
          },
        },
      });

      expect(e.prefill.amountPaisa, isNull);
      expect(e.warnings, hasLength(3));
      expect(e.warnings.first.code, 'unknown');
      expect(e.warnings.first.message, 'Check this value.');
      expect(e.lineItems, hasLength(3));
      expect(e.lineItems[2].description, isNull);
      expect(e.lineItems[2].quantityText, isNull);
      expect(e.printedSubtotal.isEmpty, isTrue);
      expect(e.printedTax.isEmpty, isTrue);
    });

    test('an amount of zero is kept as zero, not as missing', () {
      final e = ReceiptExtraction.fromResponse({
        'data': {
          'prefill': {'tax_paisa': 0},
          'receipt': {
            'printed': {
              'tax': {'text': '0.00', 'paisa': 0},
            },
          },
        },
      });
      expect(e.prefill.taxPaisa, 0);
      expect(e.printedTax.paisa, 0);
      expect(e.printedTax.isEmpty, isFalse);
    });

    test(
      'an amount whose text could not be read keeps the text and has no value',
      () {
        final e = ReceiptExtraction.fromResponse({
          'data': {
            'receipt': {
              'printed': {
                'tax': {'text': '13%', 'paisa': null},
              },
            },
          },
        });
        expect(e.printedTax.text, '13%');
        expect(e.printedTax.paisa, isNull);
      },
    );
  });
}
