import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/api/health_client.dart';
import 'package:hisabai/core/config/api_config.dart';
import 'package:hisabai/features/health/health_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget screenWith(MockClient mock) => MaterialApp(
  home: HealthScreen(
    client: HealthClient(
      config: const ApiConfig(baseUrl: 'http://api.test'),
      httpClient: mock,
    ),
  ),
);

void main() {
  testWidgets('shows success when the API is healthy', (tester) async {
    final mock = MockClient(
      (_) async => http.Response(
        jsonEncode({'status': 'ok'}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    await tester.pumpWidget(screenWith(mock));
    await tester.pumpAndSettle();

    expect(find.text('API is reachable'), findsOneWidget);
  });

  testWidgets('shows a useful error, then recovers on retry', (tester) async {
    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('refused');
      return http.Response(
        jsonEncode({'status': 'ok'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(screenWith(mock));
    await tester.pumpAndSettle();

    expect(find.text('Connection problem'), findsOneWidget);
    expect(find.textContaining('http://api.test'), findsOneWidget);

    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    expect(find.text('API is reachable'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('shows a database warning when the API is degraded', (
    tester,
  ) async {
    final mock = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'status': 'degraded',
          'checks': {'database': 'unavailable'},
        }),
        503,
        headers: {'content-type': 'application/json'},
      ),
    );

    await tester.pumpWidget(screenWith(mock));
    await tester.pumpAndSettle();

    expect(find.text('Server reachable, database unavailable'), findsOneWidget);
  });
}
