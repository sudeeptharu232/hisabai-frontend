import '../../core/api/api_exception.dart';

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.isSystem,
    this.slug,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String?,
      isSystem: json['is_system'] as bool,
    );
  }

  final String id;
  final String name;
  final String? slug;
  final bool isSystem;
}

/// How the date printed on the bill was written, as chosen by the user.
/// The app never converts between calendars; `expenseDate` is always the AD date
/// the user confirmed.
enum PrintedCalendar {
  unknown('unknown', 'Not sure'),
  ad('AD', 'AD (Gregorian)'),
  bs('BS', 'BS (Bikram Sambat)');

  const PrintedCalendar(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PrintedCalendar fromApi(String value) {
    return PrintedCalendar.values.firstWhere(
      (c) => c.apiValue == value,
      orElse: () => PrintedCalendar.unknown,
    );
  }
}

/// Formats a date as `YYYY-MM-DD`, the API's date format.
String formatApiDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class Expense {
  const Expense({
    required this.id,
    required this.merchantName,
    required this.amountPaisa,
    required this.currency,
    required this.category,
    required this.expenseDate,
    required this.originalCalendar,
    this.createdBy,
    this.subtotalPaisa,
    this.taxPaisa,
    this.originalDateText,
    this.notes,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    final categoryJson = json['category'];
    if (categoryJson is! Map<String, dynamic>) {
      throw const UnexpectedResponseException(
        'The server sent an expense without a category.',
      );
    }
    return Expense(
      id: json['id'] as String,
      createdBy: json['created_by'] as int?,
      merchantName: json['merchant_name'] as String,
      amountPaisa: json['amount_paisa'] as int,
      currency: json['currency'] as String,
      subtotalPaisa: json['subtotal_paisa'] as int?,
      taxPaisa: json['tax_paisa'] as int?,
      category: ExpenseCategory.fromJson(categoryJson),
      expenseDate: DateTime.parse(json['expense_date'] as String),
      originalDateText: json['original_date_text'] as String?,
      originalCalendar:
          PrintedCalendar.fromApi(json['original_calendar'] as String),
      notes: json['notes'] as String?,
    );
  }

  final String id;
  final int? createdBy;
  final String merchantName;
  final int amountPaisa;
  final String currency;
  final int? subtotalPaisa;
  final int? taxPaisa;
  final ExpenseCategory category;
  final DateTime expenseDate;
  final String? originalDateText;
  final PrintedCalendar originalCalendar;
  final String? notes;
}

class ExpensePage {
  const ExpensePage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<Expense> items;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;
}

/// What the form submits. Optional fields that are null are sent as null, which
/// clears them on the server when editing.
class ExpenseInput {
  const ExpenseInput({
    required this.merchantName,
    required this.amountPaisa,
    required this.categoryId,
    required this.expenseDate,
    required this.originalCalendar,
    this.originalDateText,
    this.subtotalPaisa,
    this.taxPaisa,
    this.notes,
  });

  final String merchantName;
  final int amountPaisa;
  final String categoryId;
  final DateTime expenseDate;
  final PrintedCalendar originalCalendar;
  final String? originalDateText;
  final int? subtotalPaisa;
  final int? taxPaisa;
  final String? notes;

  Map<String, Object?> toJson() => {
        'merchant_name': merchantName.trim(),
        'amount_paisa': amountPaisa,
        'category_id': categoryId,
        'expense_date': formatApiDate(expenseDate),
        'original_calendar': originalCalendar.apiValue,
        'original_date_text': _blankToNull(originalDateText),
        'subtotal_paisa': subtotalPaisa,
        'tax_paisa': taxPaisa,
        'notes': _blankToNull(notes),
      };

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
