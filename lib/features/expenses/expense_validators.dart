import '../../core/money/money.dart';
import 'expense_models.dart';

/// Client-side checks for quick feedback. The server repeats every one of them and
/// remains authoritative.
class ExpenseValidators {
  const ExpenseValidators._();

  static String? merchantName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter the supplier or shop name';
    if (text.length > 150) return 'Use at most 150 characters';
    return null;
  }

  /// A required amount in rupees, e.g. `1,250.50`.
  static String? amount(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter the amount';
    final paisa = parseRupeesToPaisa(value);
    if (paisa == null) return 'Enter an amount like 1250.50';
    if (paisa <= 0) return 'The amount must be more than zero';
    if (paisa > maxPaisa) return 'The amount is too large';
    return null;
  }

  /// An optional amount: blank is fine; anything typed must be valid.
  static String? optionalAmount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final paisa = parseRupeesToPaisa(value);
    if (paisa == null) return 'Enter an amount like 100.00';
    if (paisa > maxPaisa) return 'The amount is too large';
    return null;
  }

  static String? category(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return 'Choose a category';
    return null;
  }

  static String? notes(String? value) {
    if ((value?.length ?? 0) > 1000) return 'Use at most 1000 characters';
    return null;
  }

  /// BS dates must be typed exactly as printed; the app never converts them.
  static String? printedDate(PrintedCalendar calendar, String? value) {
    final text = value?.trim() ?? '';
    if (text.length > 32) return 'Use at most 32 characters';
    if (calendar == PrintedCalendar.bs) {
      if (text.isEmpty) return 'Type the date exactly as printed on the bill';
      final pattern = RegExp(
        r'^[0-9\u0966-\u096F]{1,4}[-/.][0-9\u0966-\u096F]{1,2}[-/.][0-9\u0966-\u096F]{1,4}$',
      );
      if (!pattern.hasMatch(text)) return 'Use a date like 2083/06/15';
    }
    return null;
  }

  /// Mirrors the server rule: subtotal + tax must equal the total, give or take
  /// NPR 1.00 of rounding. Returns a message for the tax field, or null.
  static String? moneyConsistency({
    required int? amountPaisa,
    required int? subtotalPaisa,
    required int? taxPaisa,
  }) {
    if (amountPaisa == null) return null;
    if (taxPaisa != null && taxPaisa > amountPaisa) {
      return 'The tax cannot be larger than the total';
    }
    if (subtotalPaisa != null && subtotalPaisa > amountPaisa + roundingTolerancePaisa) {
      return 'The subtotal cannot be larger than the total';
    }
    if (subtotalPaisa != null && taxPaisa != null) {
      final difference = (subtotalPaisa + taxPaisa - amountPaisa).abs();
      if (difference > roundingTolerancePaisa) {
        return 'Subtotal plus tax must equal the total (up to NPR 1.00 rounding)';
      }
    }
    return null;
  }

  /// The AD date must be a real date from 2000 up to today.
  static String? date(DateTime? value, DateTime today) {
    if (value == null) return 'Choose the date';
    final day = DateTime(value.year, value.month, value.day);
    final limit = DateTime(today.year, today.month, today.day);
    if (day.isAfter(limit)) return 'The date cannot be in the future';
    if (day.year < 2000) return 'The date must be 2000 or later';
    return null;
  }
}
