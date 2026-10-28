/// Money helpers. Amounts are ALWAYS integer paisa (1 NPR = 100 paisa); floating
/// point is never used to hold, add, or convert money.
///
/// Display format: `NPR 1,23,456.78` - ASCII digits, South Asian grouping (the last
/// three digits, then groups of two), always two decimal places.
library;

/// NPR 100,000,000.00 - the API's upper limit (config/expenses.php on the server).
const int maxPaisa = 10000000000;

/// The API accepts subtotal + tax to differ from the total by up to NPR 1.00.
const int roundingTolerancePaisa = 100;

String formatNpr(int paisa) => 'NPR ${formatAmount(paisa)}';

/// `123456` -> `1,234.56`; `12345678` -> `1,23,456.78`.
String formatAmount(int paisa) {
  final negative = paisa < 0;
  final absolute = paisa.abs();
  final rupees = absolute ~/ 100;
  final fraction = (absolute % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}${_groupSouthAsian(rupees.toString())}.$fraction';
}

/// Plain `1250.50` form, for filling an edit field. No grouping.
String paisaToInputText(int paisa) {
  final rupees = paisa ~/ 100;
  final fraction = (paisa % 100).toString().padLeft(2, '0');
  return '$rupees.$fraction';
}

/// Parses what a person typed (rupees, up to two decimals) into paisa using only
/// integer arithmetic. Returns null when the text is not a valid amount.
///
/// Accepts ASCII or Devanagari digits and comma grouping: `1,250.5`, `१२५०.५०`.
/// Rejects more than two decimals, signs, exponents, and letters.
int? parseRupeesToPaisa(String? input) {
  if (input == null) return null;
  var text = input.trim().replaceAll(',', '').replaceAll(' ', '');
  text = _devanagariToAscii(text);
  final match = RegExp(r'^(\d{1,12})?(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) return null;

  final whole = match.group(1);
  final fraction = match.group(2);
  if (whole == null && fraction == null) return null;

  final rupees = whole == null ? 0 : int.parse(whole);
  final paise = fraction == null ? 0 : int.parse(fraction.padRight(2, '0'));
  return rupees * 100 + paise;
}

String _groupSouthAsian(String digits) {
  if (digits.length <= 3) return digits;
  final lastThree = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$lastThree';
}

String _devanagariToAscii(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    // Devanagari digits U+0966..U+096F map to 0..9.
    if (rune >= 0x0966 && rune <= 0x096F) {
      buffer.writeCharCode(0x30 + (rune - 0x0966));
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
