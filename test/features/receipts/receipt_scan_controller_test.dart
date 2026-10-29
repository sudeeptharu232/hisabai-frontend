import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/features/receipts/receipt_image.dart';
import 'package:hisabai/features/receipts/receipt_scan_controller.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/fake_receipt_server.dart';

void main() {
  late ReceiptHarness h;

  ReceiptScanController make(FakeReceiptImagePicker picker) =>
      ReceiptScanController(
        repository: h.receipts,
        businessId: ReceiptHarness.businessId,
        imagePicker: picker,
      );

  setUp(() => h = ReceiptHarness());

  group('choosing a photo', () {
    test('a picked photo is kept and ready; nothing is sent yet', () async {
      final c = make(FakeReceiptImagePicker([preparedImage()]));

      await c.pick(ImageSource.gallery);

      expect(c.status, ReceiptScanStatus.ready);
      expect(c.image, isNotNull);
      expect(c.canExtract, isTrue);
      expect(h.calls, isEmpty);
    });

    test('cancelling changes nothing and shows no error', () async {
      final c = make(FakeReceiptImagePicker([null]));

      await c.pick(ImageSource.camera);

      expect(c.status, ReceiptScanStatus.idle);
      expect(c.image, isNull);
      expect(c.error, isNull);
      expect(c.canExtract, isFalse);
    });

    test('cancelling later keeps the photo already chosen', () async {
      final c = make(FakeReceiptImagePicker([preparedImage(), null]));
      await c.pick(ImageSource.gallery);
      final first = c.image;

      await c.pick(ImageSource.camera);

      expect(c.image, same(first));
      expect(c.status, ReceiptScanStatus.ready);
      expect(c.error, isNull);
    });

    test('a picker error shows its message and leaves no photo', () async {
      final c = make(
        FakeReceiptImagePicker([
          const ReceiptImageException('Camera access was denied.'),
        ]),
      );

      await c.pick(ImageSource.camera);

      expect(c.error, 'Camera access was denied.');
      expect(c.status, ReceiptScanStatus.idle);
      expect(c.image, isNull);
    });

    test('a picker error keeps an earlier good photo', () async {
      final c = make(
        FakeReceiptImagePicker([
          preparedImage(),
          const ReceiptImageException('Only JPEG'),
        ]),
      );
      await c.pick(ImageSource.gallery);

      await c.pick(ImageSource.gallery);

      expect(c.error, 'Only JPEG');
      expect(c.image, isNotNull);
      expect(c.status, ReceiptScanStatus.ready);
    });

    test('a second pick while one is open is ignored', () async {
      final picker = FakeReceiptImagePicker([preparedImage()])
        ..gate = Completer<void>();
      final c = make(picker);

      final first = c.pick(ImageSource.camera);
      await c.pick(ImageSource.gallery);

      expect(c.status, ReceiptScanStatus.preparing);
      expect(picker.calls, [ImageSource.camera]);
      picker.gate!.complete();
      await first;
      expect(c.status, ReceiptScanStatus.ready);
    });
  });

  group('reading the receipt', () {
    test('sends the photo once and returns the extraction', () async {
      final c = make(FakeReceiptImagePicker([preparedImage()]));
      await c.pick(ImageSource.gallery);

      final result = await c.extract();

      expect(result, isNotNull);
      expect(result!.prefill.amountPaisa, 316400);
      expect(h.extractCalls, 1);
      expect(c.status, ReceiptScanStatus.ready);
      expect(c.error, isNull);
      expect(
        c.image,
        isNotNull,
        reason: 'the photo stays so the person can go back',
      );
    });

    test('nothing is sent without a photo', () async {
      final c = make(FakeReceiptImagePicker([]));

      expect(await c.extract(), isNull);
      expect(h.extractCalls, 0);
    });

    test('a double tap sends one request', () async {
      h.extractGate = Completer<void>();
      final c = make(FakeReceiptImagePicker([preparedImage()]));
      await c.pick(ImageSource.gallery);

      final first = c.extract();
      final second = c.extract();
      await Future<void>.delayed(Duration.zero);

      expect(c.status, ReceiptScanStatus.uploading);
      expect(c.canExtract, isFalse);
      expect(await second, isNull, reason: 'the duplicate does nothing');
      h.extractGate!.complete();
      expect(await first, isNotNull);
      expect(h.extractCalls, 1);
    });

    test('picking is ignored while uploading', () async {
      h.extractGate = Completer<void>();
      final picker = FakeReceiptImagePicker([preparedImage(), preparedImage()]);
      final c = make(picker);
      await c.pick(ImageSource.gallery);

      final reading = c.extract();
      await c.pick(ImageSource.camera);

      expect(picker.calls, [ImageSource.gallery]);
      h.extractGate!.complete();
      await reading;
    });

    test(
      'a failure keeps the photo, explains, and a retry needs no new photo',
      () async {
        h.status = 500;
        h.body = {'message': 'boom'};
        final picker = FakeReceiptImagePicker([preparedImage()]);
        final c = make(picker);
        await c.pick(ImageSource.gallery);

        expect(await c.extract(), isNull);
        expect(c.error, contains('server had a problem'));
        expect(c.image, isNotNull);
        expect(c.canExtract, isTrue);

        h.status = 200;
        h.body = extractionBody();
        final retry = await c.extract();

        expect(retry, isNotNull);
        expect(c.error, isNull);
        expect(h.extractCalls, 2);
        expect(
          picker.calls,
          hasLength(1),
          reason: 'the photo was not picked again',
        );
      },
    );

    test(
      'offline: explains the internet requirement and keeps the photo',
      () async {
        h.failure = const SocketException('unreachable');
        final c = make(FakeReceiptImagePicker([preparedImage()]));
        await c.pick(ImageSource.gallery);

        expect(await c.extract(), isNull);

        expect(c.error, contains('internet connection'));
        expect(c.image, isNotNull);
        expect(c.status, ReceiptScanStatus.ready);
      },
    );

    test('the daily quota gets its own message', () async {
      h.status = 429;
      h.body = {'message': 'x', 'code': 'business_quota_exceeded'};
      final c = make(FakeReceiptImagePicker([preparedImage()]));
      await c.pick(ImageSource.gallery);

      await c.extract();

      expect(c.error, contains('allowance for today'));
    });

    test('a malformed response is reported without detail', () async {
      h.body = {'data': 'bad'};
      final c = make(FakeReceiptImagePicker([preparedImage()]));
      await c.pick(ImageSource.gallery);

      await c.extract();

      expect(c.error, isNotNull);
      expect(c.image, isNotNull);
    });

    test('no expense is ever created by reading a receipt', () async {
      final c = make(FakeReceiptImagePicker([preparedImage()]));
      await c.pick(ImageSource.gallery);
      await c.extract();

      expect(h.createCalls, 0);
      expect(h.expenses.expenses, isEmpty);
    });
  });

  test('clear forgets the photo', () async {
    final c = make(FakeReceiptImagePicker([preparedImage()]));
    await c.pick(ImageSource.gallery);

    c.clear();

    expect(c.image, isNull);
    expect(c.status, ReceiptScanStatus.idle);
  });

  test('disposing while a request is running does not crash', () async {
    h.extractGate = Completer<void>();
    final c = make(FakeReceiptImagePicker([preparedImage()]));
    await c.pick(ImageSource.gallery);

    final reading = c.extract();
    c.dispose();
    h.extractGate!.complete();

    expect(await reading, isNotNull);
  });
}
