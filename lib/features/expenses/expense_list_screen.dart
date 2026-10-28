import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../auth/auth_models.dart';
import 'expense_detail_screen.dart';
import 'expense_form_screen.dart';
import 'expense_list_controller.dart';
import 'expense_models.dart';
import 'expense_repository.dart';

class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({
    super.key,
    required this.repository,
    required this.business,
    required this.user,
  });

  final ExpenseRepository repository;
  final BusinessSummary business;
  final AuthUser user;

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  late final ExpenseListController _controller;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = ExpenseListController(
      repository: widget.repository,
      businessId: widget.business.id,
    );
    unawaited(_controller.load());
    unawaited(_controller.loadCategories());
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _canModify(Expense expense) =>
      widget.business.isOwner || expense.createdBy == widget.user.id;

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    // Categories may have failed to load earlier; try again before opening the form.
    if (_controller.categories.isEmpty) await _controller.loadCategories();
    if (!mounted) return;
    final saved = await Navigator.of(context).push<Expense>(
      MaterialPageRoute<Expense>(
        builder: (_) => ExpenseFormScreen(
          repository: widget.repository,
          businessId: widget.business.id,
          categories: _controller.categories,
        ),
      ),
    );
    if (saved != null && mounted) {
      _snack('Expense saved');
      await _controller.load(showSpinner: false);
    }
  }

  Future<void> _open(Expense expense) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ExpenseDetailScreen(
          repository: widget.repository,
          businessId: widget.business.id,
          categories: _controller.categories,
          expense: expense,
          canModify: _canModify(expense),
        ),
      ),
    );
    if (!mounted) return;
    if (result == expenseDeletedResult) _snack('Expense deleted');
    // The expense may have been edited or deleted: always refresh quietly.
    await _controller.load(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.business.name} - expenses')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-expense'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
            children: [
              _Filters(
                controller: _controller,
                searchController: _searchController,
              ),
              Expanded(child: _content(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (_controller.status) {
      case ExpenseListStatus.loading:
        return const Center(
          child: CircularProgressIndicator(key: Key('expenses-loading')),
        );
      case ExpenseListStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  _controller.error ?? 'Could not load expenses.',
                  key: const Key('expenses-error'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('expenses-retry'),
                  onPressed: () => unawaited(_controller.load()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case ExpenseListStatus.loaded:
        if (_controller.items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _controller.hasFilters
                    ? 'No expenses match your search.'
                    : 'No expenses yet. Tap "Add expense" to record your first one.',
                key: const Key('expenses-empty'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return _list(context);
    }
  }

  Widget _list(BuildContext context) {
    final items = _controller.items;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) return _footer();
        final expense = items[index];
        return ListTile(
          key: Key('expense-${expense.id}'),
          title: Text(expense.merchantName),
          subtitle: Text('${formatApiDate(expense.expenseDate)} - ${expense.category.name}'),
          trailing: Text(
            formatNpr(expense.amountPaisa),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          onTap: () => unawaited(_open(expense)),
        );
      },
    );
  }

  Widget _footer() {
    if (_controller.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_controller.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_controller.loadMoreError!),
            TextButton(
              key: const Key('expenses-load-more'),
              onPressed: () => unawaited(_controller.loadMore()),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_controller.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: TextButton(
          key: const Key('expenses-load-more'),
          onPressed: () => unawaited(_controller.loadMore()),
          child: Text('Load more (${_controller.items.length} of ${_controller.total})'),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller, required this.searchController});

  final ExpenseListController controller;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          TextField(
            key: const Key('expense-search'),
            controller: searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by supplier',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: controller.query.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('expense-search-clear'),
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchController.clear();
                        unawaited(controller.setQuery(''));
                      },
                    ),
            ),
            onSubmitted: (value) => unawaited(controller.setQuery(value)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            key: const Key('expense-category-filter'),
            initialValue: controller.categoryId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(child: Text('All categories')),
              for (final c in controller.categories)
                DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
            ],
            onChanged: (value) => unawaited(controller.setCategory(value)),
          ),
        ],
      ),
    );
  }
}
