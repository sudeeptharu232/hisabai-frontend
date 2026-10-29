import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hisabai/core/api/api_client.dart';
import 'package:hisabai/core/storage/token_store.dart';
import 'package:hisabai/features/expenses/expense_repository.dart';
import 'package:hisabai/features/receipts/receipt_image.dart';
import 'package:hisabai/features/receipts/receipt_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import 'fake_expense_server.dart';
import 'test_support.dart';

/// Bytes that start like a JPEG (the app checks the first bytes, not the name).
Uint8List jpegBytes([int extra = 32]) =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(extra, 0x41)]);

/// A photo that is ready to send.
PreparedReceiptImage preparedImage([Uint8List? bytes]) => PreparedReceiptImage(
  bytes: bytes ?? jpegBytes(),
  filename: 'receipt.jpg',
  mimeType: 'image/jpeg',
);

Map<String, Object?> _amount(String text, int paisa) => {
  'text': text,
  'paisa': paisa,
};

const _noAmount = {'text': null, 'paisa': null};

/// The `receipt` block of a response, in the server's real shape.
Map<String, Object?> receiptJson({
  String calendar = 'AD',
  String dateText = '2026-10-27',
  String? adDate = '2026-10-27',
  List<Object?>? lineItems,
}) => {
  'is_receipt': true,
  'legibility': 'clear',
  'supplier': {'name': 'Himal Traders'},
  'printed_date': {'text': dateText, 'calendar': calendar, 'ad_date': adDate},
  'currency': {'code': 'NPR', 'text': 'Rs.', 'supported': true},
  'line_items':
      lineItems ??
      [
        {
          'index': 0,
          'description': 'Rice 5kg',
          'quantity': {'text': '2', 'value': 2.0},
          'unit_price': _amount('1,250.00', 125000),
          'line_total': _amount('2,500.00', 250000),
        },
        {
          'index': 1,
          'description': 'Sugar 1kg',
          'quantity': {'text': '3', 'value': 3.0},
          'unit_price': _amount('120.00', 12000),
          'line_total': _amount('360.00', 36000),
        },
      ],
  'printed': {
    'subtotal': _amount('2,860.00', 286000),
    'discount': _amount('60.00', 6000),
    'tax': _amount('364.00', 36400),
    'total': _amount('3,164.00', 316400),
  },
  'calculated': {'total_matches': true},
  'model_notes': <Object?>[],
};

const discountWarning = {
  'code': 'subtotal_adjusted_for_discount',
  'field': 'subtotal_paisa',
  'message':
      'The prefilled subtotal is the printed subtotal minus the printed discount.',
};

/// A successful extraction of the discounted synthetic receipt (AD date).
Map<String, Object?> extractionBody({
  Map<String, Object?>? prefill,
  List<Object?>? omitted,
  List<Object?>? warnings,
  Map<String, Object?>? receipt,
}) => {
  'data': {
    'prefill':
        prefill ??
        {
          'merchant_name': 'Himal Traders',
          'amount_paisa': 316400,
          'currency': 'NPR',
          'subtotal_paisa': 280000,
          'tax_paisa': 36400,
          'expense_date': '2026-10-27',
          'original_date_text': '2026-10-27',
          'original_calendar': 'AD',
        },
    'prefill_omitted': omitted ?? <Object?>[],
    'receipt': receipt ?? receiptJson(),
    'warnings': warnings ?? [discountWarning],
  },
  'meta': {'model': 'm', 'prompt_version': 'v2', 'cached': false, 'usage': {}},
};

/// The same receipt with a Bikram Sambat date: no AD date may be suggested.
Map<String, Object?> bsExtractionBody() => extractionBody(
  prefill: {
    'merchant_name': 'Himal Traders',
    'amount_paisa': 316400,
    'currency': 'NPR',
    'subtotal_paisa': 280000,
    'tax_paisa': 36400,
    'expense_date': null,
    'original_date_text': '2083/06/30',
    'original_calendar': 'BS',
  },
  omitted: [
    {
      'field': 'expense_date',
      'reason': 'bs_date_not_converted',
      'message': 'A BS date is never converted. Choose the AD date yourself.',
    },
  ],
  warnings: [
    discountWarning,
    {
      'code': 'date_bs_needs_confirmation',
      'field': 'printed_date_text',
      'message': 'The date is printed in the BS calendar.',
    },
  ],
  receipt: receiptJson(calendar: 'BS', dateText: '2083/06/30', adDate: null),
);

/// A response that has almost nothing in it (optional parts missing).
Map<String, Object?> sparseExtractionBody() => {
  'data': {
    'prefill': {'amount_paisa': 5000},
  },
};

/// Scripts the extraction endpoint and delegates everything else (sign-in check,
/// categories, expenses) to [FakeExpenseServer]. Has its own client instead of
/// TestApp because TestApp reads `request.body` as UTF-8, which a JPEG is not.
class ReceiptHarness {
  ReceiptHarness({FakeExpenseServer? expenses, bool signedIn = true})
    : expenses = expenses ?? FakeExpenseServer() {
    tokenStore = InMemoryTokenStore(signedIn ? FakeExpenseServer.token : null);
    api = ApiClient(
      config: testConfig,
      httpClient: MockClient(_handle),
      tokenStore: tokenStore,
      timeout: const Duration(seconds: 2),
    );
    receipts = ReceiptRepository(api: api, timeout: const Duration(seconds: 2));
    expenseRepository = ExpenseRepository(api: api);
  }

  final FakeExpenseServer expenses;
  late final InMemoryTokenStore tokenStore;
  late final ApiClient api;
  late final ReceiptRepository receipts;
  late final ExpenseRepository expenseRepository;

  static const businessId = FakeExpenseServer.businessId;
  static const extractPath = '/api/v1/businesses/$businessId/receipts/extract';

  // What the extraction endpoint does next.
  Map<String, Object?> body = extractionBody();
  int status = 200;
  Object? failure; // thrown instead of answering (SocketException, ...)
  String? rawBody; // sent as the body instead of JSON
  Completer<void>? extractGate; // the request waits for this
  Completer<void>? createGate; // POST /expenses waits for this
  int? createStatus; // POST /expenses answers with this error status
  Object? createFailure; // POST /expenses throws this (SocketException, ...)
  final Completer<void> never =
      Completer<void>(); // never completed: for timeouts
  bool hangExtract = false;

  final List<http.Request> extractRequests = [];
  final List<String> calls = [];

  int get extractCalls => extractRequests.length;

  int get createCalls => calls
      .where((c) => c == 'POST /api/v1/businesses/$businessId/expenses')
      .length;

  Future<http.Response> _handle(http.Request request) async {
    calls.add('${request.method} ${request.url.path}');

    if (request.url.path == extractPath) {
      extractRequests.add(request);
      if (hangExtract) await never.future;
      if (extractGate != null) await extractGate!.future;
      if (failure != null) throw failure!;
      if (rawBody != null) {
        return http.Response(
          rawBody!,
          status,
          headers: {'content-type': 'application/json'},
        );
      }
      return jsonResponse(status, body);
    }

    if (request.method == 'POST' &&
        request.url.path == '/api/v1/businesses/$businessId/expenses') {
      createBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (createGate != null) await createGate!.future;
      if (createFailure != null) throw createFailure!;
      if (createStatus != null) {
        return jsonResponse(createStatus!, {
          'message': 'Something internal broke.',
        });
      }
    }
    return expenses.handle(request);
  }

  /// The request body as text without decoding it as UTF-8.
  static String bodyText(http.Request request) =>
      latin1.decode(request.bodyBytes);

  /// The JSON body of every `POST /expenses` call, in order.
  final List<Map<String, dynamic>> createBodies = [];
}

/// Replaces image_picker in tests. [results] are returned one per call: a
/// [PreparedReceiptImage], null (the person cancelled) or an [Exception] to throw.
class FakeReceiptImagePicker extends ReceiptImagePicker {
  FakeReceiptImagePicker(this.results);

  final List<Object?> results;
  final List<ImageSource> calls = [];
  Completer<void>? gate;

  @override
  Future<PreparedReceiptImage?> pick(ImageSource source) async {
    calls.add(source);
    if (gate != null) await gate!.future;
    final next = results.removeAt(0);
    if (next is Exception) throw next;
    return next as PreparedReceiptImage?;
  }
}
