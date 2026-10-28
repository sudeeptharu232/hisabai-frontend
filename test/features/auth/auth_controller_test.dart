import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/api/api_exception.dart';
import 'package:hisabai/features/auth/auth_controller.dart';
import 'package:http/http.dart' as http;

import '../../support/test_support.dart';

void main() {
  group('restore', () {
    test(
      'without a stored token -> unauthenticated, no request made',
      () async {
        final app = TestApp((_) async => jsonResponse(500));

        await app.auth.restore();

        expect(app.auth.status, AuthStatus.unauthenticated);
        expect(app.seen, isEmpty);
      },
    );

    test(
      'with a valid token -> authenticated with user and business',
      () async {
        final app = TestApp(
          (_) async => jsonResponse(200, meJson(businesses: [businessJson()])),
          storedToken: '1|hisabai_ok',
        );

        await app.auth.restore();

        expect(app.auth.status, AuthStatus.authenticated);
        expect(app.auth.session!.user.name, 'Sita Sharma');
        expect(app.auth.session!.business!.name, 'Himal Kirana Pasal');
        expect(app.auth.session!.business!.isOwner, isTrue);
        expect(app.seen.single.headers['Authorization'], 'Bearer 1|hisabai_ok');
      },
    );

    test(
      'with a rejected token -> unauthenticated and the token is erased',
      () async {
        final app = TestApp(
          (_) async => jsonResponse(401, {'message': 'Unauthenticated.'}),
          storedToken: '1|hisabai_revoked',
        );

        await app.auth.restore();

        expect(app.auth.status, AuthStatus.unauthenticated);
        expect(await app.tokenStore.read(), isNull);
      },
    );

    test('offline -> restoreFailed and the token is kept for retry', () async {
      final app = TestApp(
        (_) async => throw http.ClientException('offline'),
        storedToken: '1|hisabai_ok',
      );

      await app.auth.restore();

      expect(app.auth.status, AuthStatus.restoreFailed);
      expect(app.auth.restoreError, isNotNull);
      expect(await app.tokenStore.read(), '1|hisabai_ok');
    });
  });

  group('login / register / logout', () {
    test('login stores the token, then verifies it with GET /me', () async {
      final app = TestApp((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return jsonResponse(200, tokenJson(token: '7|hisabai_new'));
        }
        return jsonResponse(200, meJson());
      });

      await app.auth.login(
        email: ' Sita@Example.com ',
        password: 'secret-pass-1',
      );

      expect(app.auth.status, AuthStatus.authenticated);
      expect(await app.tokenStore.read(), '7|hisabai_new');
      expect(app.requestKeys, ['POST /api/v1/auth/login', 'GET /api/v1/me']);
      expect(app.seen.first.body, contains('"email":"Sita@Example.com"'));
      expect(app.seen.first.headers.containsKey('Authorization'), isFalse);
      expect(app.seen.last.headers['Authorization'], 'Bearer 7|hisabai_new');
    });

    test(
      'failed login leaves the user signed out and stores nothing',
      () async {
        final app = TestApp(
          (_) async => jsonResponse(401, {
            'message': 'These credentials do not match our records.',
          }),
        );

        await expectLater(
          app.auth.login(email: 'a@b.c', password: 'wrong'),
          throwsA(isA<UnauthorizedException>()),
        );

        expect(await app.tokenStore.read(), isNull);
      },
    );

    test('register surfaces server validation errors', () async {
      final app = TestApp(
        (_) async => jsonResponse(422, {
          'message': 'The email has already been taken.',
          'errors': {
            'email': ['The email has already been taken.'],
          },
        }),
      );

      await expectLater(
        app.auth.register(
          name: 'S',
          email: 'taken@example.com',
          password: 'password123',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.fieldMessages()['email'],
            'email message',
            'The email has already been taken.',
          ),
        ),
      );
    });

    test(
      'logout revokes the token on the server and erases it locally',
      () async {
        final app = TestApp((request) async {
          if (request.url.path == '/api/v1/auth/logout')
            return jsonResponse(204);
          return jsonResponse(200, meJson());
        }, storedToken: '1|hisabai_ok');
        await app.auth.restore();

        await app.auth.logout();

        expect(app.auth.status, AuthStatus.unauthenticated);
        expect(app.auth.session, isNull);
        expect(await app.tokenStore.read(), isNull);
        expect(app.requestKeys, contains('POST /api/v1/auth/logout'));
      },
    );

    test(
      'logout still signs out locally when the server is unreachable',
      () async {
        final app = TestApp((request) async {
          if (request.url.path == '/api/v1/auth/logout') {
            throw http.ClientException('offline');
          }
          return jsonResponse(200, meJson());
        }, storedToken: '1|hisabai_ok');
        await app.auth.restore();

        await app.auth.logout();

        expect(app.auth.status, AuthStatus.unauthenticated);
        expect(await app.tokenStore.read(), isNull);
      },
    );

    test('a 401 on any later authenticated call signs the user out', () async {
      var calls = 0;
      final app = TestApp((_) async {
        calls++;
        return calls == 1
            ? jsonResponse(200, meJson())
            : jsonResponse(401, {'message': 'Unauthenticated.'});
      }, storedToken: '1|hisabai_ok');
      await app.auth.restore();
      expect(app.auth.status, AuthStatus.authenticated);

      await expectLater(
        app.auth.refresh(),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(app.auth.status, AuthStatus.unauthenticated);
      expect(await app.tokenStore.read(), isNull);
    });
  });

  group('business membership calls', () {
    test('createBusiness posts the name then refreshes the session', () async {
      var created = false;
      final app = TestApp((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/businesses') {
          created = true;
          return jsonResponse(201, {'data': businessJson()});
        }
        return jsonResponse(
          200,
          meJson(businesses: created ? [businessJson()] : []),
        );
      }, storedToken: '1|hisabai_ok');
      await app.auth.restore();
      expect(app.auth.session!.business, isNull);

      await app.auth.createBusiness('  Himal Kirana Pasal ');

      expect(app.auth.session!.business!.name, 'Himal Kirana Pasal');
      expect(
        app.seen.any(
          (s) =>
              s.key == 'POST /api/v1/businesses' &&
              s.body.contains('"name":"Himal Kirana Pasal"'),
        ),
        isTrue,
      );
    });

    test('createInvitation returns the one-time code', () async {
      final app = TestApp((request) async {
        if (request.url.path.endsWith('/invitations')) {
          return jsonResponse(201, {
            'data': {
              'id': 'x',
              'code': 'hbinv_abc123',
              'expires_at': '2026-10-20T04:46:16+00:00',
            },
          });
        }
        return jsonResponse(200, meJson(businesses: [businessJson()]));
      }, storedToken: '1|hisabai_ok');
      await app.auth.restore();

      final invitation = await app.auth.createInvitation(
        app.auth.session!.business!.id,
      );

      expect(invitation.code, 'hbinv_abc123');
      expect(invitation.expiresAt.isUtc, isTrue);
    });

    test(
      'an unexpected response shape becomes UnexpectedResponseException',
      () async {
        final app = TestApp(
          (_) async => jsonResponse(200, {
            'data': {'unexpected': true},
          }),
          storedToken: '1|hisabai_ok',
        );

        await app.auth.restore();

        expect(app.auth.status, AuthStatus.restoreFailed);
      },
    );
  });
}
