import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

/// The server's upload limit: `RECEIPTS_MAX_UPLOAD_KB`, 6144 KB by default
/// (config/receipts.php). The server stays authoritative and answers 422 if its own
/// setting is lower; this copy only avoids sending a file that is certain to fail.
const int receiptMaxUploadBytes = 6144 * 1024;

/// A photo that is safe to send: a supported format, within the size limit.
class PreparedReceiptImage {
  const PreparedReceiptImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    this.wasShrunk = false,
  });

  final Uint8List bytes;

  /// A neutral name. The picked file's own name (which can reveal device paths or
  /// camera naming) is never sent.
  final String filename;
  final String mimeType;

  /// True when the photo was larger than the limit and was scaled down.
  final bool wasShrunk;

  int get sizeBytes => bytes.length;
}

/// A problem with the picked image, worded for the person using the app.
class ReceiptImageException implements Exception {
  const ReceiptImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Formats the server accepts (JPEG, PNG, WebP). HEIC is not accepted.
enum ReceiptImageFormat {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp');

  const ReceiptImageFormat(this.mimeType, this.extension);

  final String mimeType;
  final String extension;
}

/// Detects the format from the file's first bytes, never from its name.
ReceiptImageFormat? detectReceiptImageFormat(Uint8List bytes) {
  bool startsWith(List<int> signature, {int offset = 0}) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0xFF, 0xD8, 0xFF])) return ReceiptImageFormat.jpeg;
  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return ReceiptImageFormat.png;
  }
  // WebP: "RIFF" <4 size bytes> "WEBP"
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      startsWith(const [0x57, 0x45, 0x42, 0x50], offset: 8)) {
    return ReceiptImageFormat.webp;
  }
  return null;
}

/// Scales an image so its longest side is at most [maxSide] pixels and returns it as
/// a PNG (lossless, accepted by the server), or null when it cannot be made smaller
/// that way (already small enough, or not decodable).
typedef ImageShrinker =
    Future<Uint8List?> Function(Uint8List bytes, int maxSide);

/// The real [ImageShrinker], using only the Flutter engine (no extra package).
Future<Uint8List?> shrinkToPng(Uint8List bytes, int maxSide) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= maxSide && height <= maxSide) return null;

    final landscape = width >= height;
    codec = await descriptor.instantiateCodec(
      targetWidth: landscape ? maxSide : null,
      targetHeight: landscape ? null : maxSide,
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// Picks a receipt photo (camera or gallery) with `image_picker` and makes sure it is
/// something the server will accept.
///
/// The picker already scales the photo down and compresses it, writing a new file in
/// the app's cache: the original in the gallery is never touched. If the result is
/// still over the server's limit it is scaled down further, step by step, from the
/// picked file.
class ReceiptImagePicker {
  ReceiptImagePicker({
    ImagePicker? picker,
    ImageShrinker? shrinker,
    this.maxBytes = receiptMaxUploadBytes,
  }) : _picker = picker ?? ImagePicker(),
       _shrink = shrinker ?? shrinkToPng;

  final ImagePicker _picker;
  final ImageShrinker _shrink;
  final int maxBytes;

  /// Longest side asked of the picker. Matches the server's own limit
  /// (`RECEIPTS_MAX_DIMENSION`, 2560), so nothing larger is ever useful.
  static const int firstMaxSide = 2560;

  /// JPEG quality asked of the picker (it only applies to JPEG).
  static const int imageQuality = 85;

  /// Longest sides tried, in order, when the photo is still over the limit. Below
  /// about 1000 px the small print on a receipt stops being readable, so it stops there.
  static const List<int> shrinkLadder = [1920, 1440, 1080];

  /// Opens the camera or gallery. Returns null when the person cancels. Throws a
  /// [ReceiptImageException] for permission problems and unusable images.
  Future<PreparedReceiptImage?> pick(ImageSource source) async {
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: firstMaxSide.toDouble(),
        maxHeight: firstMaxSide.toDouble(),
        imageQuality: imageQuality,
      );
    } on PlatformException catch (e) {
      throw ReceiptImageException(_pickerMessage(e.code, source));
    }
    if (file == null) return null;

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Exception {
      throw const ReceiptImageException(
        'This image could not be read. Try another photo.',
      );
    }
    return prepare(bytes);
  }

  /// Validates [bytes] and shrinks them if they are over the size limit.
  Future<PreparedReceiptImage> prepare(Uint8List bytes) async {
    final format = detectReceiptImageFormat(bytes);
    if (format == null) {
      throw const ReceiptImageException(
        'Only JPEG, PNG or WebP photos can be used. Take a new photo or choose a different image.',
      );
    }
    if (bytes.length <= maxBytes) {
      return PreparedReceiptImage(
        bytes: bytes,
        filename: 'receipt.${format.extension}',
        mimeType: format.mimeType,
      );
    }

    var decodedAtLeastOnce = false;
    for (final side in shrinkLadder) {
      Uint8List? smaller;
      try {
        smaller = await _shrink(bytes, side);
      } on Exception {
        smaller = null;
      }
      if (smaller == null) continue;
      decodedAtLeastOnce = true;
      if (smaller.length <= maxBytes) {
        return PreparedReceiptImage(
          bytes: smaller,
          filename: 'receipt.png',
          mimeType: ReceiptImageFormat.png.mimeType,
          wasShrunk: true,
        );
      }
    }

    throw ReceiptImageException(
      decodedAtLeastOnce
          ? 'This photo is too large (over ${maxBytes ~/ (1024 * 1024)} MB) even after shrinking it. Take a new photo or choose a smaller image.'
          : 'This photo is over ${maxBytes ~/ (1024 * 1024)} MB and could not be made smaller. Take a new photo or choose a smaller image.',
    );
  }

  static String _pickerMessage(String code, ImageSource source) {
    switch (code) {
      case 'camera_access_denied':
        return 'Camera access was denied. Allow the camera for HisabAI in your phone settings, or choose a photo from the gallery.';
      case 'photo_access_denied':
        return 'Photo access was denied. Allow it for HisabAI in your phone settings, or take a photo with the camera.';
      case 'already_active':
        return 'The camera or gallery is already open.';
      default:
        return source == ImageSource.camera
            ? 'The camera could not be opened. Try again, or choose a photo from the gallery.'
            : 'The gallery could not be opened. Try again, or take a photo with the camera.';
    }
  }
}
