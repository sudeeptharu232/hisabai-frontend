import '../../core/api/api_exception.dart';
import '../expenses/expense_models.dart' show PrintedCalendar;

// Parsing is deliberately forgiving about OPTIONAL parts: a missing or oddly typed
// value becomes null and is shown as "not read", never guessed. Only a response with
// no `data` object at all is treated as malformed.

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is int ? value : null;

bool? _bool(Object? value) => value is bool ? value : null;

List<Object?> _list(Object? value) => value is List<Object?> ? value : const [];

/// An amount as the server reports it: the text as printed, and the integer paisa
/// parsed from it (null when the text could not be read as an exact amount).
class ReceiptAmount {
  const ReceiptAmount({this.text, this.paisa});

  factory ReceiptAmount.fromJson(Object? json) {
    final map = _map(json);
    return ReceiptAmount(
      text: _string(map?['text']),
      paisa: _int(map?['paisa']),
    );
  }

  static const ReceiptAmount none = ReceiptAmount();

  final String? text;
  final int? paisa;

  bool get isEmpty => text == null && paisa == null;
}

class ReceiptLineItem {
  const ReceiptLineItem({
    this.description,
    this.quantityText,
    this.unitPrice = ReceiptAmount.none,
    this.lineTotal = ReceiptAmount.none,
  });

  factory ReceiptLineItem.fromJson(Object? json) {
    final map = _map(json);
    return ReceiptLineItem(
      description: _string(map?['description']),
      quantityText: _string(_map(map?['quantity'])?['text']),
      unitPrice: ReceiptAmount.fromJson(map?['unit_price']),
      lineTotal: ReceiptAmount.fromJson(map?['line_total']),
    );
  }

  final String? description;
  final String? quantityText;
  final ReceiptAmount unitPrice;
  final ReceiptAmount lineTotal;
}

class ReceiptWarning {
  const ReceiptWarning({required this.code, required this.message, this.field});

  factory ReceiptWarning.fromJson(Object? json) {
    final map = _map(json);
    return ReceiptWarning(
      code: _string(map?['code']) ?? 'unknown',
      field: _string(map?['field']),
      message: _string(map?['message']) ?? 'Check this value.',
    );
  }

  final String code;
  final String? field;
  final String message;
}

/// A value the server read but did NOT put in the prefill, and why.
class OmittedField {
  const OmittedField({
    required this.field,
    required this.reason,
    required this.message,
  });

  factory OmittedField.fromJson(Object? json) {
    final map = _map(json);
    return OmittedField(
      field: _string(map?['field']) ?? 'unknown',
      reason: _string(map?['reason']) ?? 'unknown',
      message: _string(map?['message']) ?? 'This value was not filled in.',
    );
  }

  final String field;
  final String reason;
  final String message;
}

/// What `POST /expenses` will accept as it is. Any value may be null (not read, or
/// not safe to suggest). `expenseDate` is only set for a confirmed AD date.
class ReceiptPrefill {
  const ReceiptPrefill({
    this.merchantName,
    this.amountPaisa,
    this.currency,
    this.subtotalPaisa,
    this.taxPaisa,
    this.expenseDate,
    this.originalDateText,
    this.originalCalendar = PrintedCalendar.unknown,
  });

  factory ReceiptPrefill.fromJson(Object? json) {
    final map = _map(json);
    final dateText = _string(map?['expense_date']);
    return ReceiptPrefill(
      merchantName: _string(map?['merchant_name']),
      amountPaisa: _int(map?['amount_paisa']),
      currency: _string(map?['currency']),
      subtotalPaisa: _int(map?['subtotal_paisa']),
      taxPaisa: _int(map?['tax_paisa']),
      expenseDate: _apiDate(dateText),
      originalDateText: _string(map?['original_date_text']),
      originalCalendar: PrintedCalendar.fromApi(
        _string(map?['original_calendar']) ?? 'unknown',
      ),
    );
  }

  final String? merchantName;
  final int? amountPaisa;
  final String? currency;
  final int? subtotalPaisa;
  final int? taxPaisa;
  final DateTime? expenseDate;
  final String? originalDateText;
  final PrintedCalendar originalCalendar;

  /// Only a plain `YYYY-MM-DD` counts; anything else is not trusted as a date.
  static DateTime? _apiDate(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}

/// The whole `data` block of a successful extraction.
class ReceiptExtraction {
  const ReceiptExtraction({
    required this.prefill,
    required this.omitted,
    required this.warnings,
    required this.lineItems,
    this.supplierName,
    this.printedDateText,
    this.printedCalendar = PrintedCalendar.unknown,
    this.currencyCode,
    this.currencySupported,
    this.printedSubtotal = ReceiptAmount.none,
    this.printedDiscount = ReceiptAmount.none,
    this.printedTax = ReceiptAmount.none,
    this.printedTotal = ReceiptAmount.none,
    this.modelNotes = const [],
    this.cached = false,
  });

  /// Builds the extraction from the decoded JSON body. Throws
  /// [UnexpectedResponseException] when there is no `data` object.
  factory ReceiptExtraction.fromResponse(Map<String, dynamic> json) {
    final data = _map(json['data']);
    if (data == null) {
      throw const UnexpectedResponseException(
        'The server sent a response this app could not understand.',
      );
    }
    final receipt = _map(data['receipt']);
    final printed = _map(receipt?['printed']);
    final printedDate = _map(receipt?['printed_date']);
    final currency = _map(receipt?['currency']);

    return ReceiptExtraction(
      prefill: ReceiptPrefill.fromJson(data['prefill']),
      omitted: _list(
        data['prefill_omitted'],
      ).map(OmittedField.fromJson).toList(),
      warnings: _list(data['warnings']).map(ReceiptWarning.fromJson).toList(),
      lineItems: _list(
        receipt?['line_items'],
      ).map(ReceiptLineItem.fromJson).toList(),
      supplierName: _string(_map(receipt?['supplier'])?['name']),
      printedDateText: _string(printedDate?['text']),
      printedCalendar: PrintedCalendar.fromApi(
        _string(printedDate?['calendar']) ?? 'unknown',
      ),
      currencyCode: _string(currency?['code']),
      currencySupported: _bool(currency?['supported']),
      printedSubtotal: ReceiptAmount.fromJson(printed?['subtotal']),
      printedDiscount: ReceiptAmount.fromJson(printed?['discount']),
      printedTax: ReceiptAmount.fromJson(printed?['tax']),
      printedTotal: ReceiptAmount.fromJson(printed?['total']),
      modelNotes: _list(receipt?['model_notes']).whereType<String>().toList(),
      cached: _bool(_map(json['meta'])?['cached']) ?? false,
    );
  }

  final ReceiptPrefill prefill;
  final List<OmittedField> omitted;
  final List<ReceiptWarning> warnings;
  final List<ReceiptLineItem> lineItems;
  final String? supplierName;
  final String? printedDateText;
  final PrintedCalendar printedCalendar;
  final String? currencyCode;
  final bool? currencySupported;

  /// The amounts exactly as printed. These are shown as read and never replaced by
  /// a calculated value.
  final ReceiptAmount printedSubtotal;
  final ReceiptAmount printedDiscount;
  final ReceiptAmount printedTax;
  final ReceiptAmount printedTotal;
  final List<String> modelNotes;
  final bool cached;

  bool hasWarning(String code) => warnings.any((w) => w.code == code);

  /// True when the suggested expense subtotal is the printed subtotal minus the
  /// printed discount (an expense cannot store a discount).
  bool get subtotalAdjustedForDiscount =>
      hasWarning('subtotal_adjusted_for_discount');
}
