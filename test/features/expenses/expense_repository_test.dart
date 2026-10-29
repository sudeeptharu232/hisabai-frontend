import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/api/api_exception.dart';
import 'package:hisabai/features/expenses/expense_models.dart';
import 'package:http/http.dart' as http;

import '../../support/test_support.dart';

const businessId = '0198a3c4-0000-7000-8000-000000000001';

Map<String, Object?> expenseJson({
  String id = 'exp-1',
  String merchant = 'Himal Traders',
  int amountPaisa = 125050,
  String calendar = 'unknown',
  String? printed,
  int? subtotal,
  int? tax,
}) => {
  'id': id,
  'business_id': businessId,
  'created_by': 1,
  'merchant_name': merchant,
  'amount_paisa': amountPaisa,
  'currency': 'NPR',
  'subtotal_paisa': subtotal,
  'tax_paisa': tax,
  'category': {
    'id': 'cat-rent',
    'name': 'Rent',
    'slug': 'rent',
    'is_system': true,
    'created_at': null,
  },
  'category_id': 'cat-rent',
  'expense_date': '2026-10-01',
  'original_date_text': printed,
  'original_calendar': calendar,
  'notes': null,
  'created_at': '2026-10-17T00:00:00+00:00',
  'updated_at': '2026-10-17T00:00:00+00:00',
};

TestApp appWith(http.Response Function(http.Request) respond) =>
    TestApp((request) async => respond(request), storedToken: '1|hisabai_t');

void main() {
  group('parsing', () {
    test(
      'an expense keeps exact paisa, the AD date, and the printed BS date',
      () async {
        final app = appWith(
          (_) => jsonResponse(200, {
            'data': expenseJson(
              amountPaisa: 9999999999,
              calendar: 'BS',
              printed: '२०८३/०६/१५',
              subtotal: 9000000000,
              tax: 999999999,
            ),
          }),
        );

        final expense = await app.expenseRepository.getExpense(
          businessId,
          'exp-1',
        );

        expect(expense.amountPaisa, 9999999999);
        expect(expense.subtotalPaisa, 9000000000);
        expect(expense.taxPaisa, 999999999);
        expect(expense.expenseDate, DateTime(2026, 10, 1));
        expect(expense.originalCalendar, PrintedCalendar.bs);
        expect(expense.originalDateText, '२०८३/०६/१५');
        expect(expense.category.slug, 'rent');
        expect(expense.category.isSystem, isTrue);
      },
    );

    test(
      'an unexpected response shape becomes UnexpectedResponseException',
      () async {
        final app = appWith(
          (_) => jsonResponse(200, {
            'data': {'id': 'x', 'merchant_name': 'No amount'},
          }),
        );

        await expectLater(
          app.expenseRepository.getExpense(businessId, 'x'),
          throwsA(isA<UnexpectedResponseException>()),
        );
      },
    );

    test('an expense without a category is rejected', () async {
      final json = expenseJson()..remove('category');
      final app = appWith((_) => jsonResponse(200, {'data': json}));

      await expectLater(
        app.expenseRepository.getExpense(businessId, 'exp-1'),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });
  });

  group('requests', () {
    test(
      'listExpenses sends page, size and only the filters that are set',
      () async {
        late Uri url;
        final app = appWith((request) {
          url = request.url;
          return jsonResponse(200, {
            'data': [expenseJson()],
            'meta': {
              'current_page': 2,
              'last_page': 3,
              'per_page': 10,
              'total': 25,
            },
          });
        });

        final page = await app.expenseRepository.listExpenses(
          businessId,
          page: 2,
          perPage: 10,
          query: '  ram ',
          categoryId: 'cat-rent',
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 30),
        );

        expect(url.path, '/api/v1/businesses/$businessId/expenses');
        expect(url.queryParameters, {
          'page': '2',
          'per_page': '10',
          'q': 'ram',
          'category_id': 'cat-rent',
          'from': '2026-09-01',
          'to': '2026-09-30',
        });
        expect(page.items, hasLength(1));
        expect(page.currentPage, 2);
        expect(page.total, 25);
        expect(page.hasMore, isTrue);
      },
    );

    test('listExpenses omits blank search and unset filters', () async {
      late Map<String, String> params;
      final app = appWith((request) {
        params = request.url.queryParameters;
        return jsonResponse(200, {
          'data': <Object?>[],
          'meta': {
            'current_page': 1,
            'last_page': 1,
            'per_page': 20,
            'total': 0,
          },
        });
      });

      final page = await app.expenseRepository.listExpenses(
        businessId,
        query: '   ',
      );

      expect(params, {'page': '1', 'per_page': '20'});
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test(
      'createExpense posts integer paisa, the AD date and the printed date as typed',
      () async {
        late http.Request seen;
        final app = appWith((request) {
          seen = request;
          return jsonResponse(201, {'data': expenseJson()});
        });

        await app.expenseRepository.createExpense(
          businessId,
          ExpenseInput(
            merchantName: '  Himal Traders ',
            amountPaisa: 125050,
            categoryId: 'cat-rent',
            expenseDate: DateTime(2026, 10, 2),
            originalCalendar: PrintedCalendar.bs,
            originalDateText: ' २०८३/०६/१५ ',
            subtotalPaisa: 100000,
            taxPaisa: 25050,
            notes: '   ',
          ),
        );

        expect(seen.method, 'POST');
        expect(seen.url.path, '/api/v1/businesses/$businessId/expenses');
        final body = jsonDecode(seen.body) as Map<String, dynamic>;
        expect(body['merchant_name'], 'Himal Traders');
        expect(body['amount_paisa'], 125050);
        expect(body['amount_paisa'], isA<int>());
        expect(body['subtotal_paisa'], 100000);
        expect(body['tax_paisa'], 25050);
        expect(body['expense_date'], '2026-10-02');
        expect(body['original_calendar'], 'BS');
        expect(body['original_date_text'], '२०८३/०६/१५');
        expect(body['notes'], isNull);
        expect(body.containsKey('business_id'), isFalse);
        expect(body.containsKey('created_by'), isFalse);
        expect(seen.body, contains('"amount_paisa":125050'));
      },
    );

    test('updateExpense uses PATCH on the expense URL', () async {
      late http.Request seen;
      final app = appWith((request) {
        seen = request;
        return jsonResponse(200, {'data': expenseJson(merchant: 'Renamed')});
      });

      final updated = await app.expenseRepository.updateExpense(
        businessId,
        'exp-1',
        ExpenseInput(
          merchantName: 'Renamed',
          amountPaisa: 100,
          categoryId: 'cat-rent',
          expenseDate: DateTime(2026, 10, 2),
          originalCalendar: PrintedCalendar.unknown,
        ),
      );

      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/api/v1/businesses/$businessId/expenses/exp-1');
      expect(updated.merchantName, 'Renamed');
    });

    test('deleteExpense uses DELETE', () async {
      late http.Request seen;
      final app = appWith((request) {
        seen = request;
        return jsonResponse(204);
      });

      await app.expenseRepository.deleteExpense(businessId, 'exp-1');

      expect(seen.method, 'DELETE');
      expect(seen.url.path, '/api/v1/businesses/$businessId/expenses/exp-1');
    });

    test('listCategories parses built-in and custom categories', () async {
      final app = appWith(
        (_) => jsonResponse(200, {
          'data': [
            {'id': 'a', 'name': 'Rent', 'slug': 'rent', 'is_system': true},
            {
              'id': 'b',
              'name': 'Festival stock',
              'slug': null,
              'is_system': false,
            },
          ],
        }),
      );

      final categories = await app.expenseRepository.listCategories(businessId);

      expect(categories.map((c) => c.name), ['Rent', 'Festival stock']);
      expect(categories.last.isSystem, isFalse);
      expect(categories.last.slug, isNull);
    });
  });

  group('server errors', () {
    test('422 carries field messages', () async {
      final app = appWith(
        (_) => jsonResponse(422, {
          'message': 'The amount paisa field must be an integer.',
          'errors': {
            'amount_paisa': ['The amount paisa field must be an integer.'],
          },
        }),
      );

      await expectLater(
        app.expenseRepository.createExpense(
          businessId,
          ExpenseInput(
            merchantName: 'x',
            amountPaisa: 1,
            categoryId: 'c',
            expenseDate: DateTime(2026, 10, 1),
            originalCalendar: PrintedCalendar.unknown,
          ),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.fieldMessages()['amount_paisa'],
            'amount_paisa message',
            'The amount paisa field must be an integer.',
          ),
        ),
      );
    });

    test('404 and 403 are typed', () async {
      final notFound = appWith(
        (_) => jsonResponse(404, {'message': 'Not found.'}),
      );
      await expectLater(
        notFound.expenseRepository.getExpense(businessId, 'x'),
        throwsA(isA<NotFoundException>()),
      );

      final forbidden = appWith(
        (_) => jsonResponse(403, {'message': 'This action is unauthorized.'}),
      );
      await expectLater(
        forbidden.expenseRepository.deleteExpense(businessId, 'x'),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });
}
