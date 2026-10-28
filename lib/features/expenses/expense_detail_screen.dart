import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/money/money.dart';
import 'expense_form_screen.dart';
import 'expense_models.dart';
import 'expense_repository.dart';

/// Result returned when the expense was deleted from this screen.
const String expenseDeletedResult = 'deleted';

class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.repository,
    required this.businessId,
    required this.categories,
    required this.expense,
    required this.canModify,
  });

  final ExpenseRepository repository;
  final String businessId;
  final List<ExpenseCategory> categories;
  final Expense expense;

  /// Owners can change any expense; members only their own. The server enforces
  /// this too - hiding the buttons is just a courtesy.
  final bool canModify;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  late Expense _expense = widget.expense;
  bool _deleting = false;

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<Expense>(
      MaterialPageRoute<Expense>(
        builder: (_) => ExpenseFormScreen(
          repository: widget.repository,
          businessId: widget.businessId,
          categories: widget.categories,
          existing: _expense,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _expense = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changes saved')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text(
          '${_expense.merchantName}, ${formatNpr(_expense.amountPaisa)}. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.repository.deleteExpense(widget.businessId, _expense.id);
      if (!mounted) return;
      Navigator.of(context).pop(expenseDeletedResult);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _expense;
    final printed = e.originalDateText;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense'),
        actions: [
          if (widget.canModify) ...[
            IconButton(
              key: const Key('edit-expense'),
              tooltip: 'Edit',
              icon: const Icon(Icons.edit),
              onPressed: _deleting ? null : () => unawaited(_edit()),
            ),
            IconButton(
              key: const Key('delete-expense'),
              tooltip: 'Delete',
              icon: const Icon(Icons.delete),
              onPressed: _deleting ? null : () => unawaited(_confirmDelete()),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              formatNpr(e.amountPaisa),
              key: const Key('detail-amount'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(e.merchantName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _Row(label: 'Category', value: e.category.name),
            _Row(label: 'Date (AD)', value: formatApiDate(e.expenseDate)),
            if (printed != null)
              _Row(
                label: 'Printed date',
                value: '$printed (${e.originalCalendar.apiValue})',
              ),
            if (e.subtotalPaisa != null)
              _Row(label: 'Subtotal', value: formatNpr(e.subtotalPaisa!)),
            if (e.taxPaisa != null) _Row(label: 'Tax', value: formatNpr(e.taxPaisa!)),
            if (e.notes != null) _Row(label: 'Notes', value: e.notes!),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
