import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/features/receipts/receipt_image.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/fake_receipt_server.dart';

Uint8List _png() => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0,
  0,
  0,
  0,
]);

Uint8List _webp() => Uint8List.fromList([
  0x52,
  0x49,
  0x46,
  0x46,
  1,
  2,
  3,
  4,
  0x57,
  0x45,
  0x42,
  0x50,
  0x56,
]);

/// Looks like HEIC: "....ftypheic". The server does not accept it.
Uint8List _heic() => Uint8List.fromList([
  0,
  0,
  0,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x68,
  0x65,
  0x69,
  0x63,
]);

/// Stands in for image_picker's ImagePicker. Records the call and answers with
/// a file, a cancel (null) or a platform error.
class _FakePicker extends Fake implements ImagePicker {
  _FakePicker({this.file, this.error});

  final XFile? file;
  final Object? error;
  Invocation? last;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #pickImage) {
      last = invocation;
      if (error != null) return Future<XFile?>.error(error!);
      return Future<XFile?>.value(file);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('format detection (by content, not by name)', () {
    test('recognises JPEG, PNG and WebP', () {
      expect(detectReceiptImageFormat(jpegBytes()), ReceiptImageFormat.jpeg);
      expect(detectReceiptImageFormat(_png()), ReceiptImageFormat.png);
      expect(detectReceiptImageFormat(_webp()), ReceiptImageFormat.webp);
    });

    test('rejects HEIC, GIF, text and empty or tiny input', () {
      expect(detectReceiptImageFormat(_heic()), isNull);
      expect(
        detectReceiptImageFormat(
          Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
        ),
        isNull,
      );
      expect(
        detectReceiptImageFormat(Uint8List.fromList('hello'.codeUnits)),
        isNull,
      );
      expect(detectReceiptImageFormat(Uint8List(0)), isNull);
      expect(
        detectReceiptImageFormat(Uint8List.fromList([0xFF, 0xD8])),
        isNull,
      );
    });

    test('RIFF without WEBP is not WebP', () {
      final wav = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        1,
        2,
        3,
        4,
        0x57,
        0x41,
        0x56,
        0x45,
      ]);
      expect(detectReceiptImageFormat(wav), isNull);
    });
  });

  group('prepare: validation and size', () {
    test('a small JPEG passes unchanged with a neutral file name', () async {
      final original = jpegBytes();
      final copy = Uint8List.fromList(original);

      final result = await ReceiptImagePicker().prepare(original);

      expect(result.bytes, copy, reason: 'the bytes are not altered');
      expect(result.filename, 'receipt.jpg');
      expect(result.mimeType, 'image/jpeg');
      expect(result.wasShrunk, isFalse);
    });

    test('PNG and WebP keep their format', () async {
      final png = await ReceiptImagePicker().prepare(_png());
      expect((png.filename, png.mimeType), ('receipt.png', 'image/png'));
      final webp = await ReceiptImagePicker().prepare(_webp());
      expect((webp.filename, webp.mimeType), ('receipt.webp', 'image/webp'));
    });

    test('an unsupported image is refused with a clear message', () async {
      for (final bytes in [
        _heic(),
        Uint8List(0),
        Uint8List.fromList('text'.codeUnits),
      ]) {
        await expectLater(
          ReceiptImagePicker().prepare(bytes),
          throwsA(
            isA<ReceiptImageException>().having(
              (e) => e.message,
              'message',
              contains('JPEG, PNG or WebP'),
            ),
          ),
        );
      }
    });

    test('the server limit is 6144 KB', () {
      expect(receiptMaxUploadBytes, 6144 * 1024);
    });

    test('a file exactly at the limit is sent as it is', () async {
      final shrinkCalls = <int>[];
      final picker = ReceiptImagePicker(
        maxBytes: jpegBytes(46).length,
        shrinker: (bytes, side) async {
          shrinkCalls.add(side);
          return null;
        },
      );

      final result = await picker.prepare(jpegBytes(46));

      expect(result.wasShrunk, isFalse);
      expect(shrinkCalls, isEmpty);
    });

    test(
      'one byte over the limit is shrunk, trying smaller sizes in order',
      () async {
        final tried = <int>[];
        final big = jpegBytes(46);
        final picker = ReceiptImagePicker(
          maxBytes: big.length - 1,
          shrinker: (bytes, side) async {
            tried.add(side);
            // too large at 1920, small enough at 1440
            return side == 1920 ? Uint8List(big.length + 10) : Uint8List(10);
          },
        );

        final result = await picker.prepare(big);

        expect(tried, [
          1920,
          1440,
        ], reason: 'stops at the first size that fits');
        expect(result.wasShrunk, isTrue);
        expect(result.filename, 'receipt.png');
        expect(result.mimeType, 'image/png');
        expect(result.sizeBytes, 10);
      },
    );

    test('still too large after every step is refused', () async {
      final big = jpegBytes(46);
      final tried = <int>[];
      final picker = ReceiptImagePicker(
        maxBytes: 10,
        shrinker: (bytes, side) async {
          tried.add(side);
          return Uint8List(big.length);
        },
      );

      await expectLater(
        picker.prepare(big),
        throwsA(
          isA<ReceiptImageException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
      expect(tried, ReceiptImagePicker.shrinkLadder);
    });

    test('an image that cannot be shrunk is refused', () async {
      final picker = ReceiptImagePicker(
        maxBytes: 10,
        shrinker: (b, s) async => null,
      );

      await expectLater(
        picker.prepare(jpegBytes(46)),
        throwsA(
          isA<ReceiptImageException>().having(
            (e) => e.message,
            'message',
            contains('could not be made smaller'),
          ),
        ),
      );
    });

    test('a shrinker that throws counts as "cannot shrink"', () async {
      final picker = ReceiptImagePicker(
        maxBytes: 10,
        shrinker: (b, s) async => throw Exception('decode failed'),
      );

      await expectLater(
        picker.prepare(jpegBytes(46)),
        throwsA(isA<ReceiptImageException>()),
      );
    });

    test('the ladder never goes below a legible size', () {
      expect(
        ReceiptImagePicker.shrinkLadder.reduce((a, b) => a < b ? a : b),
        greaterThanOrEqualTo(1000),
      );
    });
  });

  group('pick: the camera and the gallery', () {
    test('cancelling returns null and is not an error', () async {
      final picker = ReceiptImagePicker(picker: _FakePicker());

      expect(await picker.pick(ImageSource.gallery), isNull);
    });

    test(
      'asks the picker for a resized, compressed image from the chosen source',
      () async {
        final fake = _FakePicker(
          file: XFile.fromData(jpegBytes(), name: 'IMG_0001.jpg'),
        );
        final result = await ReceiptImagePicker(
          picker: fake,
        ).pick(ImageSource.camera);

        final args = fake.last!.namedArguments;
        expect(args[#source], ImageSource.camera);
        expect(args[#maxWidth], 2560.0);
        expect(args[#maxHeight], 2560.0);
        expect(args[#imageQuality], 85);
        expect(result, isNotNull);
        expect(
          result!.filename,
          'receipt.jpg',
          reason: 'the device file name is not sent',
        );
      },
    );

    test(
      'a denied camera permission gives a message that says what to do',
      () async {
        final picker = ReceiptImagePicker(
          picker: _FakePicker(
            error: PlatformException(code: 'camera_access_denied'),
          ),
        );

        await expectLater(
          picker.pick(ImageSource.camera),
          throwsA(
            isA<ReceiptImageException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('Camera access was denied'),
                )
                .having((e) => e.message, 'message', contains('gallery')),
          ),
        );
      },
    );

    test('a denied photo permission suggests the camera', () async {
      final picker = ReceiptImagePicker(
        picker: _FakePicker(
          error: PlatformException(code: 'photo_access_denied'),
        ),
      );

      await expectLater(
        picker.pick(ImageSource.gallery),
        throwsA(
          isA<ReceiptImageException>().having(
            (e) => e.message,
            'message',
            contains('camera'),
          ),
        ),
      );
    });

    test(
      'an unknown platform error is worded generically and leaks no details',
      () async {
        final picker = ReceiptImagePicker(
          picker: _FakePicker(
            error: PlatformException(
              code: 'weird',
              message: '/data/user/0/secret/path',
            ),
          ),
        );

        await expectLater(
          picker.pick(ImageSource.gallery),
          throwsA(
            isA<ReceiptImageException>().having(
              (e) => e.message,
              'message',
              allOf(contains('could not be opened'), isNot(contains('secret'))),
            ),
          ),
        );
      },
    );

    test('a picked file that is not a supported image is refused', () async {
      final picker = ReceiptImagePicker(
        picker: _FakePicker(file: XFile.fromData(_heic(), name: 'IMG.heic')),
      );

      await expectLater(
        picker.pick(ImageSource.gallery),
        throwsA(isA<ReceiptImageException>()),
      );
    });
  });
}
