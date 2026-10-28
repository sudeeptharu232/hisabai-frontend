import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'test_support.dart';

/// An in-memory stand-in for the expense endpoints, for UI tests.
class FakeExpenseServer {
  FakeExpenseServer({this.isOwner = true});

  static const token = '1|hisabai_fake';
  static const businessId = '0198a3c4-0000-7000-8000-000000000001';
  static const userId = 1;

  final bool isOwner;

  final List<Map<String, Object?>> categories = [
    _category('cat-inv', 'inventory_supplies', 'Inventory & supplies'),
    _category('cat-rent', 'rent', 'Rent'),
    _category('cat-other', 'other', 'Other'),
  ];
  final List<Map<String, Object?>> expenses = [];
  final List<String> requests = [];

  /// While set, expense-list requests wait for it (to observe the loading state).
  Completer<void>? listGate;

  /// The next N list requests fail with HTTP 500.
  int failListTimes = 0;

  int _nextId = 1;

  static Map<String, Object?> _category(String id, String slug, String name) => {
        'id': id,
        'name': name,
        'slug': slug,
        'is_system': true,
        'created_at': '2026-10-01T00:00:00+00:00',
      };

  int count(String key) => requests.where((r) => r == key).length;

  Map<String, Object?> seed(
    String merchant,
    int amountPaisa, {
    String categoryId = 'cat-other',
    String date = '2026-10-01',
    int createdBy = userId,
    String calendar = 'unknown',
    String? printedText,
    int? subtotal,
    int? tax,
    String? notes,
  }) {
    final expense = _build({
      'merchant_name': merchant,
      'amount_paisa': amountPaisa,
      'category_id': categoryId,
      'expense_date': date,
      'original_calendar': calendar,
      'original_date_text': printedText,
      'subtotal_paisa': subtotal,
      'tax_paisa': tax,
      'notes': notes,
    }, createdBy: createdBy);
    expenses.insert(0, expense);
    return expense;
  }

  Map<String, Object?> _build(Map<String, dynamic> body, {int createdBy = userId}) {
    final category = categories.firstWhere((c) => c['id'] == body['category_id']);
    return {
      'id': 'exp-${_nextId++}',
      'business_id': businessId,
      'created_by': createdBy,
      'merchant_name': body['merchant_name'],
      'amount_paisa': body['amount_paisa'],
      'currency': 'NPR',
      'subtotal_paisa': body['subtotal_paisa'],
      'tax_paisa': body['tax_paisa'],
      'category': category,
      'category_id': category['id'],
      'expense_date': body['expense_date'],
      'original_date_text': body['original_date_text'],
      'original_calendar': body['original_calendar'] ?? 'unknown',
      'notes': body['notes'],
      'created_at': '2026-10-17T00:00:00+00:00',
      'updated_at': '2026-10-17T00:00:00+00:00',
    };
  }

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');

    if (request.headers['Authorization'] != 'Bearer $token') {
      return jsonResponse(401, {'message': 'Unauthenticated.'});
    }
    if (request.method == 'GET' && path == '/api/v1/me') {
      return jsonResponse(
        200,
        meJson(
          user: userJson(id: userId),
          businesses: [
            businessJson(id: businessId, name: 'Himal Kirana Pasal', role: isOwner ? 'owner' : 'member'),
          ],
        ),
      );
    }

    final base = '/api/v1/businesses/$businessId';
    if (request.method == 'GET' && path == '$base/categories') {
      return jsonResponse(200, {'data': categories});
    }
    if (path == '$base/expenses') {
      if (request.method == 'GET') return _list(request);
      if (request.method == 'POST') return _create(request);
    }
    if (path.startsWith('$base/expenses/')) {
      final id = path.substring('$base/expenses/'.length);
      final index = expenses.indexWhere((e) => e['id'] == id);
      if (index < 0) return jsonResponse(404, {'message': 'Not found.'});
      switch (request.method) {
        case 'GET':
          return jsonResponse(200, {'data': expenses[index]});
        case 'PATCH':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final merged = {...expenses[index], ...body};
          final rebuilt = _build(merged.cast<String, dynamic>(), createdBy: expenses[index]['created_by']! as int);
          rebuilt['id'] = id;
          expenses[index] = rebuilt;
          return jsonResponse(200, {'data': rebuilt});
        case 'DELETE':
          expenses.removeAt(index);
          return jsonResponse(204);
      }
    }
    return jsonResponse(404, {'message': 'Not found.'});
  }

  Future<http.Response> _list(http.Request request) async {
    final gate = listGate;
    if (gate != null) await gate.future;
    if (failListTimes > 0) {
      failListTimes--;
      return jsonResponse(500, {'message': 'Server Error'});
    }

    final params = request.url.queryParameters;
    final q = params['q']?.toLowerCase();
    final categoryId = params['category_id'];
    final perPage = int.parse(params['per_page'] ?? '20');
    final page = int.parse(params['page'] ?? '1');

    final filtered = expenses.where((e) {
      if (q != null && !(e['merchant_name']! as String).toLowerCase().contains(q)) return false;
      if (categoryId != null && e['category_id'] != categoryId) return false;
      return true;
    }).toList();

    final lastPage = filtered.isEmpty ? 1 : (filtered.length / perPage).ceil();
    final start = (page - 1) * perPage;
    final slice = filtered.skip(start).take(perPage).toList();
    return jsonResponse(200, {
      'data': slice,
      'meta': {
        'current_page': page,
        'last_page': lastPage,
        'per_page': perPage,
        'total': filtered.length,
      },
    });
  }

  Future<http.Response> _create(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (body['merchant_name'] == 'REJECT') {
      return jsonResponse(422, {
        'message': 'The merchant name is not accepted.',
        'errors': {
          'merchant_name': ['The merchant name is not accepted.'],
        },
      });
    }
    final expense = _build(body);
    expenses.insert(0, expense);
    return jsonResponse(201, {'data': expense});
  }
}
