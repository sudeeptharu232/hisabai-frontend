import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/features/expenses/expense_list_controller.dart';
import 'package:http/http.dart' as http;

import '../../support/test_support.dart';
import 'expense_repository_test.dart' show businessId, expenseJson;

Map<String, Object?> pageJson(
  List<Map<String, Object?>> items, {
  int page = 1,
  int last = 1,
  int total = 0,
}) => {
  'data': items,
  'meta': {
    'current_page': page,
    'last_page': last,
    'per_page': 20,
    'total': total,
  },
};

ExpenseListController controllerFor(
  Future<http.Response> Function(http.Request) handler,
) {
  final app = TestApp(handler, storedToken: '1|hisabai_t');
  return ExpenseListController(
    repository: app.expenseRepository,
    businessId: businessId,
  );
}

void main() {
  test('starts loading, then shows the rows', () async {
    final controller = controllerFor(
      (_) async => jsonResponse(200, pageJson([expenseJson()], total: 1)),
    );
    expect(controller.status, ExpenseListStatus.loading);

    await controller.load();

    expect(controller.status, ExpenseListStatus.loaded);
    expect(controller.items, hasLength(1));
    expect(controller.total, 1);
    expect(controller.hasMore, isFalse);
  });

  test('an empty business loads as an empty list, not an error', () async {
    final controller = controllerFor(
      (_) async => jsonResponse(200, pageJson([])),
    );

    await controller.load();

    expect(controller.status, ExpenseListStatus.loaded);
    expect(controller.items, isEmpty);
  });

  test('a failure shows an error, and retrying recovers', () async {
    var calls = 0;
    final controller = controllerFor((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('offline');
      return jsonResponse(200, pageJson([expenseJson()], total: 1));
    });

    await controller.load();
    expect(controller.status, ExpenseListStatus.error);
    expect(controller.error, contains('Cannot reach the server'));

    await controller.load();
    expect(controller.status, ExpenseListStatus.loaded);
    expect(controller.error, isNull);
  });

  test('loadMore appends the next page and stops at the last one', () async {
    final controller = controllerFor((request) async {
      final page = int.parse(request.url.queryParameters['page']!);
      return jsonResponse(
        200,
        pageJson([expenseJson(id: 'exp-$page')], page: page, last: 2, total: 2),
      );
    });

    await controller.load();
    expect(controller.hasMore, isTrue);

    await controller.loadMore();

    expect(controller.items.map((e) => e.id), ['exp-1', 'exp-2']);
    expect(controller.hasMore, isFalse);

    await controller.loadMore(); // no-op at the end
    expect(controller.items, hasLength(2));
  });

  test('a failed loadMore keeps the rows and can be retried', () async {
    var failNext = false;
    final controller = controllerFor((request) async {
      final page = int.parse(request.url.queryParameters['page']!);
      if (page == 2 && failNext) throw http.ClientException('offline');
      return jsonResponse(
        200,
        pageJson([expenseJson(id: 'exp-$page')], page: page, last: 2, total: 2),
      );
    });
    await controller.load();

    failNext = true;
    await controller.loadMore();
    expect(controller.items, hasLength(1));
    expect(controller.loadMoreError, isNotNull);
    expect(controller.status, ExpenseListStatus.loaded);

    failNext = false;
    await controller.loadMore();
    expect(controller.items, hasLength(2));
    expect(controller.loadMoreError, isNull);
  });

  test(
    'search and category filters are sent to the server and reset paging',
    () async {
      final seen = <Map<String, String>>[];
      final controller = controllerFor((request) async {
        seen.add(request.url.queryParameters);
        return jsonResponse(200, pageJson([]));
      });

      await controller.load();
      await controller.setQuery('  ram ');
      await controller.setCategory('cat-rent');

      expect(seen[0].containsKey('q'), isFalse);
      expect(seen[1]['q'], 'ram');
      expect(seen[2]['q'], 'ram');
      expect(seen[2]['category_id'], 'cat-rent');
      expect(seen[2]['page'], '1');
      expect(controller.hasFilters, isTrue);

      await controller.setQuery('');
      await controller.setCategory(null);
      expect(controller.hasFilters, isFalse);
    },
  );

  test('an outdated response never overwrites a newer one', () async {
    final slow = Completer<http.Response>();
    final controller = controllerFor((request) {
      if (request.url.queryParameters['q'] == 'old') return slow.future;
      return Future.value(
        jsonResponse(200, pageJson([expenseJson(id: 'new')], total: 1)),
      );
    });

    final first = controller.setQuery('old'); // slow
    await controller.setQuery('fresh'); // fast, started later
    slow.complete(
      jsonResponse(200, pageJson([expenseJson(id: 'old')], total: 1)),
    );
    await first;

    expect(controller.items.single.id, 'new');
  });

  test('a category load failure does not break the list', () async {
    final controller = controllerFor((request) async {
      if (request.url.path.endsWith('/categories'))
        throw http.ClientException('offline');
      return jsonResponse(200, pageJson([expenseJson()], total: 1));
    });

    await controller.loadCategories();
    await controller.load();

    expect(controller.categories, isEmpty);
    expect(controller.status, ExpenseListStatus.loaded);
  });

  test('a quiet refresh keeps the rows when it fails', () async {
    var fail = false;
    final controller = controllerFor((_) async {
      if (fail) throw http.ClientException('offline');
      return jsonResponse(200, pageJson([expenseJson()], total: 1));
    });
    await controller.load();

    fail = true;
    await controller.load(showSpinner: false);

    expect(controller.items, hasLength(1));
    expect(controller.status, ExpenseListStatus.loaded);
  });

  test(
    'changing a filter during load-more does not leave pagination stuck',
    () async {
      final slowPage2 = Completer<http.Response>();
      final controller = controllerFor((request) {
        final params = request.url.queryParameters;
        if (params['page'] == '2') return slowPage2.future;
        return Future.value(
          jsonResponse(
            200,
            pageJson([expenseJson(id: 'p1')], last: 2, total: 2),
          ),
        );
      });
      await controller.load();

      final pending = controller.loadMore(); // page 2, slow
      await controller.setQuery(
        'x',
      ); // new generation while page 2 is in flight
      slowPage2.complete(
        jsonResponse(
          200,
          pageJson([expenseJson(id: 'p2')], page: 2, last: 2, total: 2),
        ),
      );
      await pending;

      expect(controller.loadingMore, isFalse);
      expect(controller.items.map((e) => e.id), ['p1']);
      await controller.loadMore(); // must be possible again
      expect(controller.loadingMore, isFalse);
    },
  );
}
