import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/api/api_client.dart';
import 'package:hisabai/core/api/api_exception.dart';
import 'package:hisabai/core/storage/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_support.dart';

ApiClient clientWith(
  Future<http.Response> Function(http.Request) handler, {
  String? token,
  Duration timeout = const Duration(seconds: 2),
}) {
  return ApiClient(
    config: testConfig,
    httpClient: MockClient(handler),
    tokenStore: InMemoryTokenStore(token),
    timeout: timeout,
  );
}

void main() {
  group('authentication header', () {
    test('sends the bearer token on authenticated calls', () async {
      late Map<String, String> headers;
      final client = clientWith((request) async {
        headers = request.headers;
        return jsonResponse(200, {'ok': true});
      }, token: '1|hisabai_abc');

      await client.get('/api/v1/me');

      expect(headers['Authorization'], 'Bearer 1|hisabai_abc');
      expect(headers['Accept'], 'application/json');
    });

    test('never sends the token on unauthenticated calls', () async {
      late Map<String, String> headers;
      final client = clientWith((request) async {
        headers = request.headers;
        return jsonResponse(200, {'ok': true});
      }, token: '1|hisabai_abc');

      await client.post(
        '/api/v1/auth/login',
        authenticated: false,
        body: {'email': 'a@b.c'},
      );

      expect(headers.containsKey('Authorization'), isFalse);
      expect(headers['Content-Type'], 'application/json');
    });

    test('fails before any request when there is no stored token', () async {
      var called = false;
      final client = clientWith((_) async {
        called = true;
        return jsonResponse(200, {});
      });

      await expectLater(
        client.get('/api/v1/me'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(called, isFalse);
    });
  });

  group('error mapping', () {
    Future<Object?> errorFor(int status, [Map<String, Object?>? body]) async {
      final client = clientWith(
        (_) async => jsonResponse(status, body),
        token: 't',
      );
      try {
        await client.get('/x');
        return null;
      } on ApiException catch (e) {
        return e;
      }
    }

    test('401 -> UnauthorizedException with the server message', () async {
      final e = await errorFor(401, {'message': 'Unauthenticated.'});
      expect(e, isA<UnauthorizedException>());
      expect((e! as ApiException).message, 'Unauthenticated.');
    });

    test('403 -> ForbiddenException', () async {
      expect(
        await errorFor(403, {'message': 'nope'}),
        isA<ForbiddenException>(),
      );
    });

    test('404 -> NotFoundException', () async {
      expect(
        await errorFor(404, {'message': 'Not found.'}),
        isA<NotFoundException>(),
      );
    });

    test('409 -> ConflictException', () async {
      final e = await errorFor(409, {
        'message': 'You already belong to a business.',
      });
      expect(e, isA<ConflictException>());
      expect((e! as ApiException).message, 'You already belong to a business.');
    });

    test('422 -> ValidationException with per-field messages', () async {
      final e = await errorFor(422, {
        'message': 'The email has already been taken.',
        'errors': {
          'email': ['The email has already been taken.'],
          'password': ['Too short.', 'Another.'],
        },
      });
      expect(e, isA<ValidationException>());
      final fields = (e! as ValidationException).fieldMessages();
      expect(fields['email'], 'The email has already been taken.');
      expect(fields['password'], 'Too short.');
    });

    test('429 -> RateLimitedException', () async {
      expect(await errorFor(429), isA<RateLimitedException>());
    });

    test('500 -> ServerException without leaking server detail', () async {
      final e = await errorFor(500, {'message': 'SQLSTATE[08006] secret host'});
      expect(e, isA<ServerException>());
      expect((e! as ApiException).message, isNot(contains('SQLSTATE')));
    });

    test('non-JSON error body still maps by status', () async {
      final client = clientWith(
        (_) async => http.Response('<html/>', 502),
        token: 't',
      );
      await expectLater(client.get('/x'), throwsA(isA<ServerException>()));
    });

    test(
      'success with a non-JSON body -> UnexpectedResponseException',
      () async {
        final client = clientWith(
          (_) async => http.Response('hello', 200),
          token: 't',
        );
        await expectLater(
          client.get('/x'),
          throwsA(isA<UnexpectedResponseException>()),
        );
      },
    );

    test('204 with an empty body returns an empty map', () async {
      final client = clientWith(
        (_) async => http.Response('', 204),
        token: 't',
      );
      expect(await client.post('/x'), isEmpty);
    });
  });

  group('connectivity', () {
    test('a connection failure -> NetworkException', () async {
      final client = clientWith(
        (_) async => throw http.ClientException('refused'),
        token: 't',
      );
      await expectLater(client.get('/x'), throwsA(isA<NetworkException>()));
    });

    test('a slow server -> NetworkException (timeout)', () async {
      final client = clientWith(
        (_) => Completer<http.Response>().future,
        token: 't',
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(client.get('/x'), throwsA(isA<NetworkException>()));
    });
  });

  group('session expiry callback', () {
    test('fires when an authenticated request gets 401', () async {
      var expired = 0;
      final client = clientWith(
        (_) async => jsonResponse(401, {'message': 'x'}),
        token: 't',
      )..onSessionExpired = () => expired++;

      await expectLater(
        client.get('/api/v1/me'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(expired, 1);
    });

    test('does not fire for a failed login (unauthenticated call)', () async {
      var expired = 0;
      final client = clientWith(
        (_) async => jsonResponse(401, {'message': 'bad'}),
      )..onSessionExpired = () => expired++;

      await expectLater(
        client.post('/api/v1/auth/login', authenticated: false, body: {}),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(expired, 0);
    });
  });
}
