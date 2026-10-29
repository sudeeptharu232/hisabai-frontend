import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/money/money.dart';
import 'expense_models.dart';
import 'expense_repository.dart';
import 'expense_validators.dart';

/// Add a new expense, or edit [existing]. Pops with the saved [Expense].
class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({
    super.key,
    required this.repository,
    required this.businessId,
    required this.categories,
    this.existing,
    this.today,
  });

  final ExpenseRepository repository;
  final String businessId;
  final List<ExpenseCategory> categories;
  final Expense? existing;

  /// Injectable "today" for tests.
  final DateTime? today;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _merchant;
  late final TextEditingController _amount;
  late final TextEditingController _subtotal;
  late final TextEditingController _tax;
  late final TextEditingController _printedDate;
  late final TextEditingController _notes;

  late DateTime _date;
  String? _categoryId;
  PrintedCalendar _calendar = PrintedCalendar.unknown;

  bool _busy = false;
  String? _formError;
  String? _dateError;
  Map<String, String> _fieldErrors = const {};

  bool get _editing => widget.existing != null;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _merchant = TextEditingController(text: e?.merchantName ?? '');
    _amount = TextEditingController(
      text: e == null ? '' : paisaToInputText(e.amountPaisa),
    );
    _subtotal = TextEditingController(
      text: e?.subtotalPaisa == null ? '' : paisaToInputText(e!.subtotalPaisa!),
    );
    _tax = TextEditingController(
      text: e?.taxPaisa == null ? '' : paisaToInputText(e!.taxPaisa!),
    );
    _printedDate = TextEditingController(text: e?.originalDateText ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _date = e?.expenseDate ?? DateTime(_today.year, _today.month, _today.day);
    _categoryId = e?.category.id;
    _calendar = e?.originalCalendar ?? PrintedCalendar.unknown;
  }

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    _subtotal.dispose();
    _tax.dispose();
    _printedDate.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime(_today.year, _today.month, _today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
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

  /// Field-level server errors, keyed by the API's field names.
  String? _server(String field) => _fieldErrors[field];

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

  Future<void> _submit() async {
    setState(() {
      _formError = null;
      _fieldErrors = const {};
      _dateError = ExpenseValidators.date(_date, _today);
    });
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _dateError != null || _categoryId == null) return;

    final input = ExpenseInput(
      merchantName: _merchant.text,
      amountPaisa: parseRupeesToPaisa(_amount.text)!,
      categoryId: _categoryId!,
      expenseDate: _date,
      originalCalendar: _calendar,
      originalDateText: _printedDate.text,
      subtotalPaisa: _subtotal.text.trim().isEmpty
          ? null
          : parseRupeesToPaisa(_subtotal.text),
      taxPaisa: _tax.text.trim().isEmpty ? null : parseRupeesToPaisa(_tax.text),
      notes: _notes.text,
    );

    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      final saved = existing == null
          ? await widget.repository.createExpense(widget.businessId, input)
          : await widget.repository.updateExpense(
              widget.businessId,
              existing.id,
              input,
            );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ValidationException catch (e) {
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit expense' : 'Add expense')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_formError != null) ...[
                Text(_formError!, style: TextStyle(color: scheme.error)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const Key('expense-merchant'),
                controller: _merchant,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Supplier or shop',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    ExpenseValidators.merchantName(v) ??
                    _server('merchant_name'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('expense-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                key: const Key('expense-category'),
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in widget.categories)
                    DropdownMenuItem<String>(value: c.id, child: Text(c.name)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _categoryId = v),
                validator: (v) =>
                    ExpenseValidators.category(v) ?? _server('category_id'),
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date (AD)',
                  border: const OutlineInputBorder(),
                  errorText: _dateError,
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(formatApiDate(_date))),
                    TextButton(
                      key: const Key('expense-date'),
                      onPressed: _busy ? null : _pickDate,
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Printed date and tax (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PrintedCalendar>(
                key: const Key('expense-calendar'),
                initialValue: _calendar,
                decoration: const InputDecoration(
                  labelText: 'Calendar used on the bill',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in PrintedCalendar.values)
                    DropdownMenuItem<PrintedCalendar>(
                      value: c,
                      child: Text(c.label),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(
                        () => _calendar = v ?? PrintedCalendar.unknown,
                      ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('expense-printed-date'),
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
                key: const Key('expense-subtotal'),
                controller: _subtotal,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Subtotal before tax (NPR)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    ExpenseValidators.optionalAmount(v) ??
                    _server('subtotal_paisa'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('expense-tax'),
                controller: _tax,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tax (NPR)',
                  border: OutlineInputBorder(),
                ),
                validator: _taxValidator,
              ),

              const SizedBox(height: 8),
              TextFormField(
                key: const Key('expense-notes'),
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    ExpenseValidators.notes(v) ?? _server('notes'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('expense-save'),
                onPressed: _busy ? null : () => unawaited(_submit()),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_editing ? 'Save changes' : 'Save expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
