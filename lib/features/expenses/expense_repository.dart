import '../../core/api/api_client.dart';
import '../auth/auth_models.dart' show parseResponse;
import 'expense_models.dart';

/// All expense and category calls. Every call is scoped to a business ID, which the
/// server verifies against the signed-in user's membership.
class ExpenseRepository {
  ExpenseRepository({required ApiClient api}) : _api = api;

  final ApiClient _api;

  static const defaultPageSize = 20;

  String _base(String businessId) => '/api/v1/businesses/$businessId';

  Future<List<ExpenseCategory>> listCategories(String businessId) async {
    final json = await _api.get('${_base(businessId)}/categories');
    return parseResponse(() {
      return (json['data'] as List<dynamic>)
          .map((c) => ExpenseCategory.fromJson(c as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ExpensePage> listExpenses(
    String businessId, {
    int page = 1,
    int perPage = defaultPageSize,
    String? query,
    String? categoryId,
    DateTime? from,
    DateTime? to,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (categoryId != null) 'category_id': categoryId,
      if (from != null) 'from': formatApiDate(from),
      if (to != null) 'to': formatApiDate(to),
    };
    final json = await _api.get(
      '${_base(businessId)}/expenses',
      query: params,
    );
    return parseResponse(() {
      final meta = json['meta'] as Map<String, dynamic>;
      return ExpensePage(
        items: (json['data'] as List<dynamic>)
            .map((e) => Expense.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentPage: meta['current_page'] as int,
        lastPage: meta['last_page'] as int,
        total: meta['total'] as int,
      );
    });
  }

  Future<Expense> getExpense(String businessId, String expenseId) async {
    final json = await _api.get('${_base(businessId)}/expenses/$expenseId');
    return parseResponse(
      () => Expense.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  Future<Expense> createExpense(String businessId, ExpenseInput input) async {
    final json = await _api.post(
      '${_base(businessId)}/expenses',
      body: input.toJson(),
    );
    return parseResponse(
      () => Expense.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  Future<Expense> updateExpense(
    String businessId,
    String expenseId,
    ExpenseInput input,
  ) async {
    final json = await _api.patch(
      '${_base(businessId)}/expenses/$expenseId',
      body: input.toJson(),
    );
    return parseResponse(
      () => Expense.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  Future<void> deleteExpense(String businessId, String expenseId) async {
    await _api.delete('${_base(businessId)}/expenses/$expenseId');
  }
}
