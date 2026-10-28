import 'dart:convert';

import 'package:http/http.dart' as http;

import 'test_support.dart';

/// A tiny in-memory stand-in for the HisabAI API, just enough for UI flows.
class FakeServer {
  FakeServer({this.validPassword = 'correct-pass-1'});

  static const token = '1|hisabai_fake';

  final String validPassword;
  final String takenEmail = 'taken@example.com';

  bool tokenValid = true;
  bool offline = false;
  Map<String, Object?>? business;
  final List<String> requests = [];

  int count(String key) => requests.where((r) => r == key).length;

  Future<http.Response> handle(http.Request request) async {
    final key = '${request.method} ${request.url.path}';
    requests.add(key);
    if (offline) throw http.ClientException('offline');

    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    final authorized =
        request.headers['Authorization'] == 'Bearer $token' && tokenValid;

    if (key == 'GET /api/v1/health') {
      return jsonResponse(200, {'status': 'ok', 'time': 'now'});
    }
    if (key == 'POST /api/v1/auth/login') {
      return body['password'] == validPassword
          ? jsonResponse(200, tokenJson(token: token))
          : jsonResponse(401, {
              'message': 'These credentials do not match our records.',
            });
    }
    if (key == 'POST /api/v1/auth/register') {
      if (body['email'] == takenEmail) {
        return jsonResponse(422, {
          'message': 'The email has already been taken.',
          'errors': {
            'email': ['The email has already been taken.'],
          },
        });
      }
      return jsonResponse(201, tokenJson(token: token));
    }

    if (!authorized) return jsonResponse(401, {'message': 'Unauthenticated.'});

    switch (key) {
      case 'GET /api/v1/me':
        return jsonResponse(
          200,
          meJson(businesses: business == null ? [] : [business!]),
        );
      case 'POST /api/v1/auth/logout':
        tokenValid = false;
        return jsonResponse(204);
      case 'POST /api/v1/businesses':
        business = businessJson(name: body['name'] as String);
        return jsonResponse(201, {'data': business});
      case 'POST /api/v1/invitations/accept':
        if (body['code'] == 'hbinv_goodcode') {
          business = businessJson(name: 'Joined Shop', role: 'member');
          return jsonResponse(200, {'data': business});
        }
        return jsonResponse(422, {
          'message': 'This invitation code is invalid or has expired.',
          'errors': {
            'code': ['This invitation code is invalid or has expired.'],
          },
        });
    }
    if (key.startsWith('POST /api/v1/businesses/') &&
        key.endsWith('/invitations')) {
      return jsonResponse(201, {
        'data': {
          'id': 'inv-1',
          'code': 'hbinv_FAKECODE1234567890',
          'expires_at': '2026-10-20T04:46:16+00:00',
        },
      });
    }
    return jsonResponse(404, {'message': 'Not found.'});
  }
}
