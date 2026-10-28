import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/money/money.dart';
import 'package:hisabai/features/expenses/expense_models.dart';
import 'package:hisabai/features/expenses/expense_validators.dart';

void main() {
  group('merchantName', () {
    test('requires a name of at most 150 characters', () {
      expect(ExpenseValidators.merchantName(null), isNotNull);
      expect(ExpenseValidators.merchantName('   '), isNotNull);
      expect(ExpenseValidators.merchantName('a' * 151), isNotNull);
      expect(ExpenseValidators.merchantName('हिमाल किराना'), isNull);
      expect(ExpenseValidators.merchantName('a' * 150), isNull);
    });
  });

  group('amount', () {
    test('requires a positive amount within the limit', () {
      expect(ExpenseValidators.amount(null), 'Enter the amount');
      expect(ExpenseValidators.amount(''), 'Enter the amount');
      expect(ExpenseValidators.amount('abc'), isNotNull);
      expect(ExpenseValidators.amount('1.234'), isNotNull);
      expect(ExpenseValidators.amount('-5'), isNotNull);
      expect(ExpenseValidators.amount('0'), 'The amount must be more than zero');
      expect(ExpenseValidators.amount('0.00'), isNotNull);
      expect(ExpenseValidators.amount('100000000.01'), 'The amount is too large');
      expect(ExpenseValidators.amount('0.01'), isNull);
      expect(ExpenseValidators.amount('1,250.50'), isNull);
      expect(ExpenseValidators.amount('100000000'), isNull);
    });
  });

  group('optionalAmount', () {
    test('allows blank but rejects invalid text', () {
      expect(ExpenseValidators.optionalAmount(null), isNull);
      expect(ExpenseValidators.optionalAmount('  '), isNull);
      expect(ExpenseValidators.optionalAmount('130'), isNull);
      expect(ExpenseValidators.optionalAmount('0'), isNull);
      expect(ExpenseValidators.optionalAmount('x'), isNotNull);
      expect(ExpenseValidators.optionalAmount('100000001'), isNotNull);
    });
  });

  test('category is required', () {
    expect(ExpenseValidators.category(null), isNotNull);
    expect(ExpenseValidators.category(''), isNotNull);
    expect(ExpenseValidators.category('abc'), isNull);
  });

  test('notes are limited to 1000 characters', () {
    expect(ExpenseValidators.notes('n' * 1000), isNull);
    expect(ExpenseValidators.notes('n' * 1001), isNotNull);
    expect(ExpenseValidators.notes(null), isNull);
  });

  group('printedDate', () {
    test('BS requires a date typed in a recognisable shape', () {
      expect(ExpenseValidators.printedDate(PrintedCalendar.bs, ''), isNotNull);
      expect(ExpenseValidators.printedDate(PrintedCalendar.bs, 'Ashwin 30'), isNotNull);
      expect(ExpenseValidators.printedDate(PrintedCalendar.bs, '2083/06/15'), isNull);
      expect(ExpenseValidators.printedDate(PrintedCalendar.bs, '२०८३/०६/१५'), isNull);
      expect(ExpenseValidators.printedDate(PrintedCalendar.bs, '15-6-2083'), isNull);
    });

    test('AD and unknown accept any text up to 32 characters, or none', () {
      expect(ExpenseValidators.printedDate(PrintedCalendar.ad, null), isNull);
      expect(ExpenseValidators.printedDate(PrintedCalendar.unknown, '01 Oct 2026'), isNull);
      expect(ExpenseValidators.printedDate(PrintedCalendar.ad, 'x' * 33), isNotNull);
    });
  });

  group('moneyConsistency', () {
    String? check(int? amount, int? subtotal, int? tax) => ExpenseValidators.moneyConsistency(
          amountPaisa: amount,
          subtotalPaisa: subtotal,
          taxPaisa: tax,
        );

    test('accepts a matching or absent breakdown', () {
      expect(check(113000, 100000, 13000), isNull);
      expect(check(113000, null, null), isNull);
      expect(check(113000, 100000, null), isNull);
      expect(check(null, 100000, 13000), isNull);
    });

    test('allows exactly the rounding tolerance and no more', () {
      expect(check(113000 + roundingTolerancePaisa, 100000, 13000), isNull);
      expect(check(113000 + roundingTolerancePaisa + 1, 100000, 13000), isNotNull);
      expect(check(113000 - roundingTolerancePaisa - 1, 100000, 13000), isNotNull);
    });

    test('rejects tax or subtotal larger than the total', () {
      expect(check(1000, null, 1001), isNotNull);
      expect(check(1000, 1000 + roundingTolerancePaisa + 1, null), isNotNull);
    });
  });

  group('date', () {
    final today = DateTime(2026, 10, 17);

    test('accepts today, leap days and the year 2000', () {
      expect(ExpenseValidators.date(DateTime(2026, 10, 17), today), isNull);
      expect(ExpenseValidators.date(DateTime(2024, 2, 29), today), isNull);
      expect(ExpenseValidators.date(DateTime(2000, 1, 1), today), isNull);
    });

    test('rejects missing, future and pre-2000 dates', () {
      expect(ExpenseValidators.date(null, today), isNotNull);
      expect(ExpenseValidators.date(DateTime(2026, 10, 18), today), isNotNull);
      expect(ExpenseValidators.date(DateTime(1999, 12, 31), today), isNotNull);
    });
  });

  test('formatApiDate pads to YYYY-MM-DD', () {
    expect(formatApiDate(DateTime(2026, 1, 5)), '2026-01-05');
    expect(formatApiDate(DateTime(2024, 2, 29)), '2024-02-29');
  });
}
