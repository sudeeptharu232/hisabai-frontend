import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/api/health_client.dart';
import 'core/config/api_config.dart';
import 'core/storage/token_store.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_repository.dart';
import 'features/expenses/expense_repository.dart';
import 'features/receipts/receipt_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // These objects live for the whole app lifetime.
  final httpClient = http.Client();
  final tokenStore = SecureTokenStore();
  final api = ApiClient(
    config: ApiConfig.fromEnvironment,
    httpClient: httpClient,
    tokenStore: tokenStore,
  );
  final auth = AuthController(
    repository: AuthRepository(api: api, tokenStore: tokenStore),
    api: api,
    tokenStore: tokenStore,
  );
  final healthClient = HealthClient(
    config: ApiConfig.fromEnvironment,
    httpClient: httpClient,
  );

  runApp(
    HisabAiApp(
      auth: auth,
      healthClient: healthClient,
      expenseRepository: ExpenseRepository(api: api),
      receiptRepository: ReceiptRepository(api: api),
    ),
  );
}
