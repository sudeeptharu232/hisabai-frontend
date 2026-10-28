import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/money/money.dart';

void main() {
  group('formatNpr', () {
    test('always shows two decimals', () {
      expect(formatNpr(0), 'NPR 0.00');
      expect(formatNpr(1), 'NPR 0.01');
      expect(formatNpr(99), 'NPR 0.99');
      expect(formatNpr(100), 'NPR 1.00');
      expect(formatNpr(125050), 'NPR 1,250.50');
    });

    test('uses South Asian digit grouping', () {
      expect(formatNpr(100000), 'NPR 1,000.00');
      expect(formatNpr(9999999), 'NPR 99,999.99');
      expect(formatNpr(12345678), 'NPR 1,23,456.78');
      expect(formatNpr(123456789), 'NPR 12,34,567.89');
      expect(formatNpr(maxPaisa), 'NPR 10,00,00,000.00');
    });

    test('is exact for large values (no floating point)', () {
      expect(formatNpr(9999999999), 'NPR 9,99,99,999.99');
      expect(formatAmount(1000000000001), '10,00,00,00,000.01');
    });
  });

  group('parseRupeesToPaisa', () {
    test('parses plain and grouped amounts exactly', () {
      expect(parseRupeesToPaisa('1250.50'), 125050);
      expect(parseRupeesToPaisa('1,250.5'), 125050);
      expect(parseRupeesToPaisa(' 1 250 '), 125000);
      expect(parseRupeesToPaisa('0.01'), 1);
      expect(parseRupeesToPaisa('.5'), 50);
      expect(parseRupeesToPaisa('7'), 700);
      expect(parseRupeesToPaisa('0'), 0);
    });

    test('accepts Devanagari digits', () {
      expect(parseRupeesToPaisa('१२५०.५०'), 125050);
      expect(parseRupeesToPaisa('१,२५०'), 125000);
    });

    test('rejects anything that is not a plain rupee amount', () {
      for (final bad in [
        '',
        '   ',
        'abc',
        '1.234',
        '5.',
        '-5',
        '+5',
        '1e3',
        '1.2.3',
        'NPR 5',
        '1234567890123',
        '.',
      ]) {
        expect(parseRupeesToPaisa(bad), isNull, reason: 'input "$bad"');
      }
      expect(parseRupeesToPaisa(null), isNull);
    });

    test('adding amounts is exact where doubles are not', () {
      // 0.1 + 0.2 != 0.3 in floating point; as paisa it is exactly 30.
      expect(parseRupeesToPaisa('0.10')! + parseRupeesToPaisa('0.20')!, parseRupeesToPaisa('0.30'));
    });

    test('round-trips through the edit-field text', () {
      for (final paisa in [1, 99, 100, 101, 125050, 9999999999, maxPaisa]) {
        expect(parseRupeesToPaisa(paisaToInputText(paisa)), paisa);
      }
      expect(paisaToInputText(125050), '1250.50');
      expect(paisaToInputText(5), '0.05');
    });
  });
}
