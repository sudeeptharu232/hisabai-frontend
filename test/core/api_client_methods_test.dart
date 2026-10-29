import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/api/api_client.dart';
import 'package:hisabai/core/api/api_exception.dart';
import 'package:hisabai/core/storage/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_support.dart';

void main() {
  late List<http.Request> seen;

  ApiClient clientReturning(http.Response Function(http.Request) respond) {
    seen = [];
    return ApiClient(
      config: testConfig,
      httpClient: MockClient((request) async {
        seen.add(request);
        return respond(request);
      }),
      tokenStore: InMemoryTokenStore('1|hisabai_t'),
    );
  }

  test('GET appends query parameters, encoded', () async {
    final client = clientReturning((_) => jsonResponse(200, {'ok': true}));

    await client.get('/api/v1/x', query: {'q': 'हिमाल & co', 'page': '2'});

    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/api/v1/x');
    expect(seen.single.url.queryParameters, {'q': 'हिमाल & co', 'page': '2'});
  });

  test('GET without query leaves the URL clean', () async {
    final client = clientReturning((_) => jsonResponse(200, {'ok': true}));

    await client.get('/api/v1/x', query: const {});

    expect(seen.single.url.toString(), 'http://api.test/api/v1/x');
  });

  test('PATCH sends a JSON body with the bearer token', () async {
    final client = clientReturning((_) => jsonResponse(200, {'ok': true}));

    await client.patch('/api/v1/x/1', body: {'amount_paisa': 125050});

    expect(seen.single.method, 'PATCH');
    expect(seen.single.body, '{"amount_paisa":125050}');
    expect(seen.single.headers['Content-Type'], 'application/json');
    expect(seen.single.headers['Authorization'], 'Bearer 1|hisabai_t');
  });

  test('DELETE returns an empty map for 204 and sends no body', () async {
    final client = clientReturning((_) => jsonResponse(204));

    final result = await client.delete('/api/v1/x/1');

    expect(result, isEmpty);
    expect(seen.single.method, 'DELETE');
    expect(seen.single.body, isEmpty);
    expect(seen.single.headers['Authorization'], 'Bearer 1|hisabai_t');
  });

  test('errors from PATCH and DELETE are typed too', () async {
    final client = clientReturning(
      (_) => jsonResponse(403, {'message': 'This action is unauthorized.'}),
    );

    await expectLater(
      client.patch('/x', body: {}),
      throwsA(isA<ForbiddenException>()),
    );
    await expectLater(client.delete('/x'), throwsA(isA<ForbiddenException>()));
  });
}
