import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../../core/api/api_exception.dart';
import 'receipt_image.dart';
import 'receipt_models.dart';
import 'receipt_repository.dart';

enum ReceiptScanStatus {
  /// No photo yet.
  idle,

  /// The camera/gallery is open, or the chosen photo is being checked and shrunk.
  preparing,

  /// A photo is ready to be read (or reading failed and it can be retried).
  ready,

  /// The photo is being sent and read.
  uploading,
}

/// State of the scan screen: pick a photo, send it, keep it for a retry if reading
/// fails. The photo is only kept in memory; nothing is queued or stored.
class ReceiptScanController extends ChangeNotifier {
  ReceiptScanController({
    required ReceiptRepository repository,
    required this.businessId,
    ReceiptImagePicker? imagePicker,
  }) : _repository = repository,
       _imagePicker = imagePicker ?? ReceiptImagePicker();

  final ReceiptRepository _repository;
  final ReceiptImagePicker _imagePicker;
  final String businessId;

  ReceiptScanStatus _status = ReceiptScanStatus.idle;
  PreparedReceiptImage? _image;
  String? _error;
  bool _disposed = false;

  ReceiptScanStatus get status => _status;
  PreparedReceiptImage? get image => _image;

  /// A message for the person, or null.
  String? get error => _error;

  bool get busy =>
      _status == ReceiptScanStatus.preparing ||
      _status == ReceiptScanStatus.uploading;

  bool get canExtract => _image != null && !busy;

  /// Opens the camera or gallery. Cancelling changes nothing (an earlier photo is
  /// kept). Ignored while something else is in progress.
  Future<void> pick(ImageSource source) async {
    if (busy) return;
    _status = ReceiptScanStatus.preparing;
    _error = null;
    _notify();

    try {
      final picked = await _imagePicker.pick(source);
      if (picked != null) _image = picked;
    } on ReceiptImageException catch (e) {
      _error = e.message;
    }
    _status = _image == null ? ReceiptScanStatus.idle : ReceiptScanStatus.ready;
    _notify();
  }

  /// Sends the photo. Returns the extraction, or null when it failed ([error] says
  /// why and the photo stays for a retry). A second call while one is running does
  /// nothing, so a double tap cannot send the photo twice.
  Future<ReceiptExtraction?> extract() async {
    final image = _image;
    if (image == null || busy) return null;

    _status = ReceiptScanStatus.uploading;
    _error = null;
    _notify();

    try {
      final extraction = await _repository.extract(businessId, image);
      _status = ReceiptScanStatus.ready;
      _notify();
      return extraction;
    } on ApiException catch (e) {
      _error = describeExtractionError(e);
      _status = ReceiptScanStatus.ready;
      _notify();
      return null;
    }
  }

  void clear() {
    if (busy) return;
    _image = null;
    _error = null;
    _status = ReceiptScanStatus.idle;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
