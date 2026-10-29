import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/money/money.dart';
import '../expenses/expense_models.dart';
import '../expenses/expense_repository.dart';
import '../expenses/expense_validators.dart';
import 'receipt_models.dart';

/// Review what was read from a receipt, correct it, and save it as an expense ONLY
/// when the person taps the confirm button. Opening this screen saves nothing.
///
/// Pops with the saved [Expense].
///
/// Three kinds of value are kept apart on screen:
///  - what the receipt PRINTS (read-only: subtotal, discount, tax, total as read),
///  - what is SUGGESTED for the expense (editable, from the server's prefill; the
///    suggested subtotal can differ from the printed one when a discount was applied),
///  - what the APP CALCULATES (the line-item total, labelled as calculated).
/// A printed amount is never replaced by a calculated one.
class ReceiptReviewScreen extends StatefulWidget {
  const ReceiptReviewScreen({
    super.key,
    required this.extraction,
    required this.expenseRepository,
    required this.businessId,
    required this.categories,
    this.today,
  });

  final ReceiptExtraction extraction;
  final ExpenseRepository expenseRepository;
  final String businessId;
  final List<ExpenseCategory> categories;

  /// Injectable "today" for tests.
  final DateTime? today;

  @override
  State<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

/// One editable line item. Line items are for review only: they are never saved.
class _ItemRow {
  _ItemRow(this.id, ReceiptLineItem? item)
    : description = TextEditingController(text: item?.description ?? ''),
      quantity = TextEditingController(text: item?.quantityText ?? ''),
      unitPrice = TextEditingController(text: _amountText(item?.unitPrice)),
      lineTotal = TextEditingController(text: _amountText(item?.lineTotal));

  final int id;
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unitPrice;
  final TextEditingController lineTotal;

  static String _amountText(ReceiptAmount? amount) {
    if (amount == null) return '';
    final paisa = amount.paisa;
    if (paisa != null) return paisaToInputText(paisa);
    return amount.text ?? '';
  }

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
    lineTotal.dispose();
  }
}

class _ReceiptReviewScreenState extends State<ReceiptReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _merchant;
  late final TextEditingController _amount;
  late final TextEditingController _subtotal;
  late final TextEditingController _tax;
  late final TextEditingController _printedDate;
  final _notes = TextEditingController();

  /// Null until the person has a confirmed AD date. Never defaulted to today.
  DateTime? _date;
  String? _categoryId;
  late PrintedCalendar _calendar;

  final List<_ItemRow> _items = [];
  int _nextItemId = 0;

  bool _saving = false;
  String? _formError;
  String? _dateError;
  Map<String, String> _fieldErrors = const {};

  ReceiptExtraction get _extraction => widget.extraction;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final prefill = _extraction.prefill;
    _merchant = TextEditingController(text: prefill.merchantName ?? '');
    _amount = TextEditingController(text: _paisaText(prefill.amountPaisa));
    _subtotal = TextEditingController(text: _paisaText(prefill.subtotalPaisa));
    _tax = TextEditingController(text: _paisaText(prefill.taxPaisa));
    _printedDate = TextEditingController(text: prefill.originalDateText ?? '');
    _date = prefill.expenseDate;
    _calendar = prefill.originalCalendar;
    for (final item in _extraction.lineItems) {
      _items.add(_ItemRow(_nextItemId++, item));
    }
  }

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    _subtotal.dispose();
    _tax.dispose();
    _printedDate.dispose();
    _notes.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  static String _paisaText(int? paisa) =>
      paisa == null ? '' : paisaToInputText(paisa);

  String? _server(String field) => _fieldErrors[field];

  Future<void> _pickDate() async {
    final today = DateTime(_today.year, _today.month, _today.day);
    final current = _date;
    final picked = await showDatePicker(
      context: context,
      // Where the calendar opens. The date stays unset until the person confirms one.
      initialDate: (current == null || current.isAfter(today))
          ? today
          : current,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Date of the expense (AD)',
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _dateError = null;
      });
    }
  }

  String? _taxValidator(String? value) {
    final own = ExpenseValidators.optionalAmount(value);
    if (own != null) return own;
    final consistency = ExpenseValidators.moneyConsistency(
      amountPaisa: parseRupeesToPaisa(_amount.text),
      subtotalPaisa: _subtotal.text.trim().isEmpty
          ? null
          : parseRupeesToPaisa(_subtotal.text),
      taxPaisa: value == null || value.trim().isEmpty
          ? null
          : parseRupeesToPaisa(value),
    );
    return consistency ?? _server('tax_paisa');
  }

  void _addItem() {
    setState(() => _items.add(_ItemRow(_nextItemId++, null)));
  }

  void _removeItem(_ItemRow row) {
    setState(() => _items.remove(row));
    // Dispose after the frame that stops using the controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  /// Sum of the line totals that can be read as amounts, or null when none can.
  /// Integer paisa only. Calculated here; it is never written into any field.
  int? _itemsTotalPaisa() {
    int? sum;
    for (final row in _items) {
      final paisa = parseRupeesToPaisa(row.lineTotal.text);
      if (paisa != null && row.lineTotal.text.trim().isNotEmpty) {
        sum = (sum ?? 0) + paisa;
      }
    }
    return sum;
  }

  Future<void> _submit() async {
    // A second tap while a save is running must do nothing.
    if (_saving) return;

    setState(() {
      _formError = null;
      _fieldErrors = const {};
      _dateError = ExpenseValidators.date(_date, _today);
    });
    final valid = _formKey.currentState?.validate() ?? false;
    final date = _date;
    final categoryId = _categoryId;
    if (!valid || _dateError != null || date == null || categoryId == null) {
      return;
    }

    final input = ExpenseInput(
      merchantName: _merchant.text,
      amountPaisa: parseRupeesToPaisa(_amount.text)!,
      categoryId: categoryId,
      expenseDate: date,
      originalCalendar: _calendar,
      originalDateText: _printedDate.text,
      subtotalPaisa: _subtotal.text.trim().isEmpty
          ? null
          : parseRupeesToPaisa(_subtotal.text),
      taxPaisa: _tax.text.trim().isEmpty ? null : parseRupeesToPaisa(_tax.text),
      notes: _notes.text,
    );

    setState(() => _saving = true);
    try {
      final saved = await widget.expenseRepository.createExpense(
        widget.businessId,
        input,
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ValidationException catch (e) {
      // Everything the person typed stays on screen so they can fix it and retry.
      if (!mounted) return;
      setState(() {
        _fieldErrors = e.fieldMessages();
        _dateError = _fieldErrors['expense_date'];
        _formError = _fieldErrors.isEmpty ? e.message : null;
      });
      _formKey.currentState?.validate();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Review receipt')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _introCard(scheme),
              if (_extraction.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _warningsCard(scheme),
              ],
              if (_extraction.omitted.isNotEmpty) ...[
                const SizedBox(height: 12),
                _omittedCard(),
              ],
              const SizedBox(height: 12),
              _printedCard(),
              if (_discountNoteVisible) ...[
                const SizedBox(height: 12),
                _discountNote(scheme),
              ],
              const SizedBox(height: 20),
              ..._expenseFields(scheme),
              const SizedBox(height: 20),
              _lineItemsCard(),
              const SizedBox(height: 24),
              if (_formError != null) ...[
                Text(
                  _formError!,
                  key: const Key('review-error'),
                  style: TextStyle(color: scheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                key: const Key('review-save'),
                onPressed: _saving ? null : () => unawaited(_submit()),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm and save expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _introCard(ColorScheme scheme) {
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'These values were read from your photo by an AI service. It can make '
          'mistakes or leave things out, so check each one. Nothing is saved '
          'until you tap "Confirm and save expense".',
          style: TextStyle(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }

  Widget _warningsCard(ColorScheme scheme) {
    return Card(
      key: const Key('review-warnings'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Things to check',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final warning in _extraction.warnings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _isInformational(warning)
                          ? Icons.info_outline
                          : Icons.warning_amber,
                      size: 20,
                      color: _isInformational(warning)
                          ? scheme.primary
                          : scheme.error,
                    ),
                    const SizedBox(width: 8),
                    // The server's text, shown as plain text.
                    Expanded(child: Text(warning.message)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _isInformational(ReceiptWarning warning) =>
      warning.code == 'subtotal_adjusted_for_discount' ||
      warning.code == 'model_note';

  static const Map<String, String> _fieldLabels = {
    'merchant_name': 'Supplier',
    'amount_paisa': 'Total',
    'subtotal_paisa': 'Subtotal',
    'tax_paisa': 'Tax',
    'expense_date': 'Date',
    'original_date_text': 'Printed date',
    'original_calendar': 'Calendar',
    'currency': 'Currency',
  };

  Widget _omittedCard() {
    return Card(
      key: const Key('review-omitted'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Not filled in for you',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final item in _extraction.omitted)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${_fieldLabels[item.field] ?? item.field}: ${item.message}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _printedCard() {
    final e = _extraction;
    final dateText = e.printedDateText;
    return Card(
      key: const Key('review-printed'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Printed on the receipt (as read)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Shown exactly as read. You cannot edit this part, and the app '
              'never changes it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _printedLine(
              'printed-supplier',
              'Supplier',
              e.supplierName ?? 'Not read',
            ),
            _printedLine(
              'printed-date',
              'Date',
              dateText == null
                  ? 'Not read'
                  : '$dateText (${e.printedCalendar.label})',
            ),
            _printedAmount('printed-subtotal', 'Subtotal', e.printedSubtotal),
            _printedAmount('printed-discount', 'Discount', e.printedDiscount),
            _printedAmount('printed-tax', 'Tax', e.printedTax),
            _printedAmount('printed-total', 'Total', e.printedTotal),
          ],
        ),
      ),
    );
  }

  Widget _printedLine(String keyName, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(child: Text(value, key: Key(keyName))),
        ],
      ),
    );
  }

  Widget _printedAmount(String keyName, String label, ReceiptAmount amount) {
    final String value;
    if (amount.isEmpty) {
      value = 'Not read';
    } else if (amount.paisa == null) {
      value = '${amount.text} (could not be read as an amount)';
    } else {
      value = '${amount.text ?? ''} (${formatNpr(amount.paisa!)})'.trim();
    }
    return _printedLine(keyName, label, value);
  }

  bool get _discountNoteVisible =>
      _extraction.subtotalAdjustedForDiscount &&
      _extraction.prefill.subtotalPaisa != null &&
      _extraction.printedSubtotal.paisa != null &&
      _extraction.printedDiscount.paisa != null;

  /// Explains why the suggested expense subtotal is not the printed subtotal.
  Widget _discountNote(ColorScheme scheme) {
    final suggested = _extraction.prefill.subtotalPaisa!;
    final printed = _extraction.printedSubtotal.paisa!;
    final discount = _extraction.printedDiscount.paisa!;
    return Card(
      key: const Key('discount-adjusted-note'),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'The suggested subtotal below (${formatNpr(suggested)}) is lower than '
          'the printed subtotal (${formatNpr(printed)}). An expense cannot store a '
          'discount and must have subtotal + tax = total, so the printed discount '
          '(${formatNpr(discount)}) was subtracted from the printed subtotal. The '
          'printed amounts above are unchanged.',
          style: TextStyle(color: scheme.onTertiaryContainer),
        ),
      ),
    );
  }

  List<Widget> _expenseFields(ColorScheme scheme) {
    final dateHint = _date == null
        ? 'No confirmed AD date was read. Choose the date yourself; a printed '
              'date is never converted for you.'
        : null;
    return [
      Text(
        'Expense to save (you can edit)',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const Key('review-merchant'),
        controller: _merchant,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Supplier or shop',
          border: OutlineInputBorder(),
        ),
        validator: (v) =>
            ExpenseValidators.merchantName(v) ?? _server('merchant_name'),
      ),
      const SizedBox(height: 16),
      if (_extraction.currencySupported == false) ...[
        Text(
          'This receipt is not in NPR. HisabAI only saves amounts in NPR, so '
          'enter the total in rupees yourself.',
          key: const Key('review-currency-note'),
          style: TextStyle(color: scheme.error),
        ),
        const SizedBox(height: 8),
      ],
      TextFormField(
        key: const Key('review-amount'),
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Total amount (NPR)',
          prefixText: 'NPR ',
          border: OutlineInputBorder(),
        ),
        validator: (v) =>
            ExpenseValidators.amount(v) ?? _server('amount_paisa'),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: const Key('review-category'),
        initialValue: _categoryId,
        isExpanded: true,
        hint: const Text('Choose a category'),
        decoration: const InputDecoration(
          labelText: 'Category',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final c in widget.categories)
            DropdownMenuItem<String>(value: c.id, child: Text(c.name)),
        ],
        onChanged: _saving ? null : (v) => setState(() => _categoryId = v),
        validator: (v) =>
            ExpenseValidators.category(v) ?? _server('category_id'),
      ),
      const SizedBox(height: 16),
      InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date (AD) - required',
          border: const OutlineInputBorder(),
          errorText: _dateError,
          helperText: dateHint,
          helperMaxLines: 3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _date == null ? 'Not set' : formatApiDate(_date!),
                key: const Key('review-date-value'),
              ),
            ),
            TextButton(
              key: const Key('review-date'),
              onPressed: _saving ? null : _pickDate,
              child: Text(_date == null ? 'Choose' : 'Change'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<PrintedCalendar>(
        key: const Key('review-calendar'),
        initialValue: _calendar,
        decoration: const InputDecoration(
          labelText: 'Calendar used on the bill',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final c in PrintedCalendar.values)
            DropdownMenuItem<PrintedCalendar>(value: c, child: Text(c.label)),
        ],
        onChanged: _saving
            ? null
            : (v) => setState(() => _calendar = v ?? PrintedCalendar.unknown),
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: const Key('review-printed-date'),
        controller: _printedDate,
        decoration: const InputDecoration(
          labelText: 'Date as printed on the bill',
          helperText: 'Saved exactly as typed. It is never converted.',
          border: OutlineInputBorder(),
        ),
        validator: (v) =>
            ExpenseValidators.printedDate(_calendar, v) ??
            _server('original_date_text'),
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: const Key('review-subtotal'),
        controller: _subtotal,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Subtotal before tax (NPR)',
          border: OutlineInputBorder(),
        ),
        validator: (v) =>
            ExpenseValidators.optionalAmount(v) ?? _server('subtotal_paisa'),
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: const Key('review-tax'),
        controller: _tax,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Tax (NPR)',
          border: OutlineInputBorder(),
        ),
        validator: _taxValidator,
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: const Key('review-notes'),
        controller: _notes,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Notes (optional)',
          border: OutlineInputBorder(),
        ),
        validator: (v) => ExpenseValidators.notes(v) ?? _server('notes'),
      ),
    ];
  }

  // ------------------------------------------------------------------ line items

  Widget _lineItemsCard() {
    final total = _itemsTotalPaisa();
    final printedSubtotal = _extraction.printedSubtotal.paisa;
    return Card(
      key: const Key('review-line-items'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Line items (for review only)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'These items are for checking the receipt only. HisabAI does not '
              'save them as structured expense items, and changing them does not '
              'change the expense above.',
              key: const Key('line-items-note'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              const Text('No items were read from the receipt.'),
            for (final row in _items) _itemEditor(row),
            TextButton.icon(
              key: const Key('add-line-item'),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
              onPressed: _saving ? null : _addItem,
            ),
            if (total != null) ...[
              const SizedBox(height: 8),
              Text(
                'Items total (calculated by the app): ${formatNpr(total)}',
                key: const Key('line-items-total'),
              ),
            ],
            if (total != null &&
                printedSubtotal != null &&
                total != printedSubtotal) ...[
              const SizedBox(height: 4),
              Text(
                'The printed subtotal is ${formatNpr(printedSubtotal)}, which '
                'differs from the items total by '
                '${formatNpr((total - printedSubtotal).abs())}. Check the items.',
                key: const Key('line-items-difference'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemEditor(_ItemRow row) {
    InputDecoration amountDecoration(String label, TextEditingController c) {
      return InputDecoration(
        labelText: label,
        errorText: ExpenseValidators.optionalAmount(c.text),
        border: const OutlineInputBorder(),
        isDense: true,
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: Key('item-description-${row.id}'),
                    controller: row.description,
                    decoration: const InputDecoration(
                      labelText: 'Item',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('remove-item-${row.id}'),
                  tooltip: 'Remove this item',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _saving ? null : () => _removeItem(row),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: Key('item-quantity-${row.id}'),
                    controller: row.quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: Key('item-unit-price-${row.id}'),
                    controller: row.unitPrice,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: amountDecoration('Unit price', row.unitPrice),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: Key('item-line-total-${row.id}'),
                    controller: row.lineTotal,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: amountDecoration('Amount', row.lineTotal),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
