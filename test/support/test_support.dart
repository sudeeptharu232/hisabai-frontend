import 'dart:convert';

import 'package:hisabai/core/api/api_client.dart';
import 'package:hisabai/core/api/health_client.dart';
import 'package:hisabai/core/config/api_config.dart';
import 'package:hisabai/core/storage/token_store.dart';
import 'package:hisabai/features/auth/auth_controller.dart';
import 'package:hisabai/features/auth/auth_repository.dart';
import 'package:hisabai/features/expenses/expense_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testConfig = ApiConfig(baseUrl: 'http://api.test');

http.Response jsonResponse(int status, [Map<String, Object?>? body]) {
  return http.Response(
    body == null ? '' : jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, Object?> userJson({
  int id = 1,
  String name = 'Sita Sharma',
  String email = 'sita@example.com',
}) => {
  'id': id,
  'name': name,
  'email': email,
  'created_at': '2026-10-17T00:00:00+00:00',
};

Map<String, Object?> businessJson({
  String id = '0198a3c4-0000-7000-8000-000000000001',
  String name = 'Himal Kirana Pasal',
  String role = 'owner',
}) => {
  'id': id,
  'name': name,
  'role': role,
  'created_at': '2026-10-17T00:00:00+00:00',
};

Map<String, Object?> meJson({
  Map<String, Object?>? user,
  List<Map<String, Object?>> businesses = const [],
}) => {
  'data': {'user': user ?? userJson(), 'businesses': businesses},
};

Map<String, Object?> tokenJson({String token = '1|hisabai_testtoken'}) => {
  'data': {
    'token': token,
    'token_type': 'Bearer',
    'expires_at': null,
    'user': userJson(),
  },
};

/// A request seen by the fake server.
class Seen {
  Seen(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;

  String get key => '$method $path';
}

/// Everything a test needs, wired the same way as main.dart.
class TestApp {
  TestApp(
    Future<http.Response> Function(http.Request request) handler, {
    String? storedToken,
  }) {
    tokenStore = InMemoryTokenStore(storedToken);
    httpClient = MockClient((request) {
      seen.add(
        Seen(request.method, request.url.path, request.headers, request.body),
      );
      return handler(request);
    });
    api = ApiClient(
      config: testConfig,
      httpClient: httpClient,
      tokenStore: tokenStore,
      timeout: const Duration(seconds: 2),
    );
    auth = AuthController(
      repository: AuthRepository(api: api, tokenStore: tokenStore),
      api: api,
      tokenStore: tokenStore,
    );
    healthClient = HealthClient(config: testConfig, httpClient: httpClient);
    expenseRepository = ExpenseRepository(api: api);
  }

  final List<Seen> seen = [];
  late final InMemoryTokenStore tokenStore;
  late final MockClient httpClient;
  late final ApiClient api;
  late final AuthController auth;
  late final HealthClient healthClient;
  late final ExpenseRepository expenseRepository;

  List<String> get requestKeys => seen.map((s) => s.key).toList();
}
