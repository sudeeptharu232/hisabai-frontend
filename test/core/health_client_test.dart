import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/api/health_client.dart';
import 'package:hisabai/core/config/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

HealthClient clientFor(
  Future<http.Response> Function(http.Request) handler, {
  Duration timeout = const Duration(seconds: 2),
}) {
  return HealthClient(
    config: const ApiConfig(baseUrl: 'http://api.test'),
    httpClient: MockClient(handler),
    timeout: timeout,
  );
}

http.Response jsonResponse(int status, Map<String, Object?> body) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('ApiConfig.uri', () {
    test('joins base URL and path without duplicate slashes', () {
      expect(
        const ApiConfig(
          baseUrl: 'http://h:8000/',
        ).uri('/api/v1/health').toString(),
        'http://h:8000/api/v1/health',
      );
      expect(
        const ApiConfig(
          baseUrl: 'http://h:8000',
        ).uri('api/v1/health').toString(),
        'http://h:8000/api/v1/health',
      );
    });
  });

  group('HealthClient.check', () {
    test(
      'returns HealthOk for 200 with status ok and requests the right URL',
      () async {
        late Uri requested;
        final client = clientFor((request) async {
          requested = request.url;
          return jsonResponse(200, {
            'status': 'ok',
            'time': '2026-10-16T00:00:00+00:00',
          });
        });

        final result = await client.check();

        expect(requested.toString(), 'http://api.test/api/v1/health');
        expect(result, isA<HealthOk>());
        expect((result as HealthOk).serverTime, '2026-10-16T00:00:00+00:00');
      },
    );

    test('returns HealthDegraded for 503 with database unavailable', () async {
      final client = clientFor(
        (_) async => jsonResponse(503, {
          'status': 'degraded',
          'checks': {'database': 'unavailable'},
        }),
      );

      final result = await client.check();

      expect(result, isA<HealthDegraded>());
      expect((result as HealthDegraded).databaseStatus, 'unavailable');
    });

    test('returns a badResponse failure for non-JSON bodies', () async {
      final client = clientFor(
        (_) async => http.Response('<html>oops</html>', 502),
      );

      final result = await client.check();

      expect(result, isA<HealthFailure>());
      expect((result as HealthFailure).reason, HealthFailureReason.badResponse);
      expect(result.message, contains('502'));
    });

    test(
      'returns an httpError failure for unexpected JSON responses',
      () async {
        final client = clientFor(
          (_) async => jsonResponse(500, {'message': 'boom'}),
        );

        final result = await client.check();

        expect((result as HealthFailure).reason, HealthFailureReason.httpError);
      },
    );

    test('does not treat 200 with a wrong status value as healthy', () async {
      final client = clientFor(
        (_) async => jsonResponse(200, {'status': 'nope'}),
      );

      expect(await client.check(), isA<HealthFailure>());
    });

    test('returns a network failure with a useful message', () async {
      final client = clientFor(
        (_) async => throw http.ClientException('connection refused'),
      );

      final result = await client.check();

      expect((result as HealthFailure).reason, HealthFailureReason.network);
      expect(result.message, contains('http://api.test'));
    });

    test('returns a timeout failure when the server is too slow', () async {
      final client = clientFor(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 50),
      );

      final result = await client.check();

      expect((result as HealthFailure).reason, HealthFailureReason.timeout);
    });
  });
}
