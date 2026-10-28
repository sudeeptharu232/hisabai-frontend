import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import 'expense_models.dart';
import 'expense_repository.dart';

enum ExpenseListStatus { loading, loaded, error }

/// State of the expense list: first-page loading, errors with retry, filters, and
/// "load more" pagination. A ChangeNotifier keeps this simple and testable.
class ExpenseListController extends ChangeNotifier {
  ExpenseListController({
    required ExpenseRepository repository,
    required this.businessId,
  }) : _repository = repository;

  final ExpenseRepository _repository;
  final String businessId;

  ExpenseListStatus _status = ExpenseListStatus.loading;
  List<Expense> _items = const [];
  List<ExpenseCategory> _categories = const [];
  String? _error;
  String? _loadMoreError;
  bool _loadingMore = false;
  int _currentPage = 0;
  int _lastPage = 0;
  int _total = 0;
  String _query = '';
  String? _categoryId;
  bool _disposed = false;

  /// Incremented by every fresh load so a slow, outdated response is ignored.
  int _generation = 0;

  ExpenseListStatus get status => _status;
  List<Expense> get items => _items;
  List<ExpenseCategory> get categories => _categories;
  String? get error => _error;
  String? get loadMoreError => _loadMoreError;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _currentPage < _lastPage;
  int get total => _total;
  String get query => _query;
  String? get categoryId => _categoryId;
  bool get hasFilters => _query.isNotEmpty || _categoryId != null;

  Future<void> loadCategories() async {
    try {
      _categories = await _repository.listCategories(businessId);
      _notify();
    } on ApiException {
      // The list still works without the filter dropdown; the form reloads them if needed.
    }
  }

  /// Loads page one with the current filters. Pass [showSpinner] false to refresh
  /// in the background while keeping the current rows on screen.
  Future<void> load({bool showSpinner = true}) async {
    final generation = ++_generation;
    // Any in-flight "load more" belongs to the previous generation and is ignored.
    _loadingMore = false;
    if (showSpinner || _items.isEmpty) {
      _status = ExpenseListStatus.loading;
      _error = null;
      _notify();
    }

    try {
      final page = await _repository.listExpenses(
        businessId,
        query: _query,
        categoryId: _categoryId,
      );
      if (generation != _generation) return;
      _items = page.items;
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
      _total = page.total;
      _loadMoreError = null;
      _error = null;
      _status = ExpenseListStatus.loaded;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      _error = e.message;
      if (_items.isEmpty || showSpinner) {
        _status = ExpenseListStatus.error;
      }
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (_loadingMore || !hasMore || _status != ExpenseListStatus.loaded) return;
    final generation = _generation;
    _loadingMore = true;
    _loadMoreError = null;
    _notify();

    try {
      final page = await _repository.listExpenses(
        businessId,
        page: _currentPage + 1,
        query: _query,
        categoryId: _categoryId,
      );
      if (generation != _generation) return;
      _items = [..._items, ...page.items];
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
      _total = page.total;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      _loadMoreError = e.message;
    } finally {
      if (generation == _generation) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  Future<void> setQuery(String value) {
    _query = value.trim();
    return load();
  }

  Future<void> setCategory(String? categoryId) {
    _categoryId = categoryId;
    return load();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
