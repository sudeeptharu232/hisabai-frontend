import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/core/api/api_exception.dart';
import 'package:hisabai/features/expenses/expense_models.dart';
import 'package:hisabai/features/receipts/receipt_repository.dart';

import '../../support/fake_expense_server.dart';
import '../../support/fake_receipt_server.dart';

void main() {
  late ReceiptHarness h;

  setUp(() => h = ReceiptHarness());

  group('the request', () {
    test(
      'is a multipart POST to the business-scoped URL with the file in "image"',
      () async {
        await h.receipts.extract(ReceiptHarness.businessId, preparedImage());

        expect(h.extractRequests, hasLength(1));
        final request = h.extractRequests.single;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/v1/businesses/${FakeExpenseServer.businessId}/receipts/extract',
        );
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );

        final body = ReceiptHarness.bodyText(request);
        expect(body, contains('name="image"'));
        expect(body, contains('filename="receipt.jpg"'));
        expect(body, isNot(contains('name="file"')));
        expect(
          body,
          contains('AAAA'),
          reason: 'the image bytes are in the body',
        );
      },
    );

    test(
      'uses the signed-in user\'s bearer token and no other credential',
      () async {
        await h.receipts.extract(ReceiptHarness.businessId, preparedImage());

        final headers = h.extractRequests.single.headers;
        expect(headers['Authorization'], 'Bearer ${FakeExpenseServer.token}');
        expect(headers['Accept'], 'application/json');
        expect(
          headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-goog-api-key')),
        );
      },
    );

    test('is scoped to the business id it is given', () async {
      await h.receipts.extract('other-business-id', preparedImage());

      expect(
        h.extractRequests.single.url.path,
        '/api/v1/businesses/other-business-id/receipts/extract',
      );
    });

    test('without a stored token nothing is sent', () async {
      final signedOut = ReceiptHarness(signedIn: false);

      await expectLater(
        signedOut.receipts.extract(ReceiptHarness.businessId, preparedImage()),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(signedOut.extractRequests, isEmpty);
    });

    test('is a preview: it makes no expense request', () async {
      await h.receipts.extract(ReceiptHarness.businessId, preparedImage());

      expect(h.calls, ['POST ${ReceiptHarness.extractPath}']);
      expect(h.expenses.expenses, isEmpty);
    });

    test(
      'allows long enough for Gemini (server: 5 s connect + 30 s) before giving up',
      () {
        expect(
          ReceiptRepository.defaultTimeout,
          greaterThan(const Duration(seconds: 35)),
        );
      },
    );
  });

  group('the response', () {
    test('is parsed from the real contract', () async {
      final result = await h.receipts.extract(
        ReceiptHarness.businessId,
        preparedImage(),
      );

      expect(result.prefill.amountPaisa, 316400);
      expect(result.prefill.subtotalPaisa, 280000);
      expect(result.printedSubtotal.paisa, 286000);
      expect(result.lineItems, hasLength(2));
    });

    test('a sparse response still works', () async {
      h.body = sparseExtractionBody();

      final result = await h.receipts.extract(
        ReceiptHarness.businessId,
        preparedImage(),
      );

      expect(result.prefill.amountPaisa, 5000);
      expect(result.lineItems, isEmpty);
    });

    test('a BS response has no AD date', () async {
      h.body = bsExtractionBody();

      final result = await h.receipts.extract(
        ReceiptHarness.businessId,
        preparedImage(),
      );

      expect(result.prefill.expenseDate, isNull);
      expect(result.prefill.originalCalendar, PrintedCalendar.bs);
    });

    test('a body that is not JSON is an error, not a crash', () async {
      h.rawBody = '<html>Bad gateway</html>';

      await expectLater(
        h.receipts.extract(ReceiptHarness.businessId, preparedImage()),
        throwsA(isA<ApiException>()),
      );
    });

    test('JSON without a data object is malformed', () async {
      h.body = {'message': 'hello'};

      await expectLater(
        h.receipts.extract(ReceiptHarness.businessId, preparedImage()),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });

    test('data of the wrong type is malformed', () async {
      h.body = {'data': 'nope'};

      await expectLater(
        h.receipts.extract(ReceiptHarness.businessId, preparedImage()),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });
  });

  group('failures', () {
    Future<ApiException> failure() async {
      try {
        await h.receipts.extract(ReceiptHarness.businessId, preparedImage());
      } on ApiException catch (e) {
        return e;
      }
      fail('expected an ApiException');
    }

    test('401 signals the expired session and is a plain message', () async {
      var expired = 0;
      h.api.onSessionExpired = () => expired++;
      h.status = 401;
      h.body = {'message': 'Unauthenticated.'};

      final error = await failure();

      expect(error, isA<UnauthorizedException>());
      expect(expired, 1);
      expect(describeExtractionError(error), contains('sign in again'));
    });

    test('422 with the image error shows that error', () async {
      h.status = 422;
      h.body = {
        'message': 'The image field must be an image.',
        'errors': {
          'image': ['The image field must be an image.'],
        },
      };

      final error = await failure();

      expect(error, isA<ValidationException>());
      expect(
        describeExtractionError(error),
        'The image field must be an image.',
      );
    });

    test(
      '422 image_unsupported and receipt_not_processed keep their code and get plain text',
      () async {
        h.status = 422;
        h.body = {
          'message': 'x',
          'code': 'image_unsupported',
          'errors': <String, Object?>{},
        };
        var error = await failure();
        expect(error.code, 'image_unsupported');
        expect(describeExtractionError(error), contains('Try another photo'));

        h.body = {
          'message': 'x',
          'code': 'receipt_not_processed',
          'errors': <String, Object?>{},
        };
        error = await failure();
        expect(describeExtractionError(error), contains('clearer photo'));
      },
    );

    test(
      '429 business_quota_exceeded keeps its code and is not the per-minute message',
      () async {
        h.status = 429;
        h.body = {
          'message': 'Daily limit reached.',
          'code': 'business_quota_exceeded',
        };

        final error = await failure();

        expect(error, isA<RateLimitedException>());
        expect(error.code, 'business_quota_exceeded');
        final text = describeExtractionError(error);
        expect(text, contains('today'));
        expect(text, isNot(contains('minute')));
      },
    );

    test('429 without a code is the per-minute limit', () async {
      h.status = 429;
      h.body = {'message': 'Too Many Attempts.'};

      final error = await failure();

      expect(error.code, isNull);
      expect(describeExtractionError(error), contains('minute'));
      expect(
        error.message,
        'Too many attempts. Please wait a minute and try again.',
        reason: 'existing wording is unchanged',
      );
    });

    test('server errors with a code get specific, safe text', () async {
      h.status = 502;
      h.body = {'message': 'x', 'code': 'upstream_unavailable'};
      expect(describeExtractionError(await failure()), contains('unavailable'));

      h.body = {'message': 'x', 'code': 'upstream_rejected'};
      expect(
        describeExtractionError(await failure()),
        contains('not set up correctly'),
      );

      h.body = {'message': 'x', 'code': 'invalid_response'};
      expect(
        describeExtractionError(await failure()),
        contains('could not be used'),
      );
    });

    test(
      'a plain 500 shows the generic server message and nothing internal',
      () async {
        h.status = 500;
        h.body = {'message': 'SQLSTATE[08006] stack trace /var/www/app.php'};

        final error = await failure();

        expect(error, isA<ServerException>());
        final text = describeExtractionError(error);
        expect(text, contains('server had a problem'));
        expect(text, isNot(contains('SQLSTATE')));
      },
    );

    test('404 says the business was not found', () async {
      h.status = 404;
      h.body = {'message': 'Not found.'};

      expect(describeExtractionError(await failure()), contains('business'));
    });

    test(
      'no connection says it needs the internet and that the photo is kept',
      () async {
        h.failure = const SocketException('Network is unreachable');

        final error = await failure();

        expect(error, isA<NetworkException>());
        final text = describeExtractionError(error);
        expect(text, contains('internet connection'));
        expect(text, contains('photo is kept'));
        expect(text, isNot(contains('Network is unreachable')));
      },
    );

    test('a request that takes too long ends as a network error', () async {
      h.hangExtract = true;
      final quick = ReceiptRepository(
        api: h.api,
        timeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        quick.extract(ReceiptHarness.businessId, preparedImage()),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
      'existing JSON error handling is unchanged (code is simply carried)',
      () async {
        h.status = 409;
        h.body = {'message': 'In use.', 'code': 'category_in_use'};

        final error = await failure();

        expect(error, isA<ConflictException>());
        expect(error.message, 'In use.');
        expect(error.code, 'category_in_use');
      },
    );
  });

  test('JSON posts still work next to the new multipart method', () async {
    final json = await h.api.get('/api/v1/me');

    expect(json['data'], isA<Map<String, dynamic>>());
    expect(h.calls, ['GET /api/v1/me']);
  });
}
