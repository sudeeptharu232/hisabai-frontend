import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../auth/auth_models.dart' show parseResponse;
import 'receipt_image.dart';
import 'receipt_models.dart';

/// Sends a receipt photo to the server for reading. The call is preview-only: the
/// server never saves an expense from it.
class ReceiptRepository {
  ReceiptRepository({required ApiClient api, this.timeout = defaultTimeout})
    : _api = api;

  final ApiClient _api;
  final Duration timeout;

  /// The server allows Gemini up to 30 s (config/receipts.php) after a 5 s connect;
  /// this adds room for uploading a few MB on a slow mobile connection.
  static const Duration defaultTimeout = Duration(seconds: 45);

  Future<ReceiptExtraction> extract(
    String businessId,
    PreparedReceiptImage image,
  ) async {
    final json = await _api.postMultipart(
      '/api/v1/businesses/$businessId/receipts/extract',
      fileField: 'image',
      bytes: image.bytes,
      filename: image.filename,
      timeout: timeout,
    );
    return parseResponse(() => ReceiptExtraction.fromResponse(json));
  }
}

/// A message for the person for a failed extraction. Uses the server's `code` where
/// that changes what they should do (the daily allowance is not the per-minute limit).
/// Never includes server internals.
String describeExtractionError(ApiException error) {
  switch (error) {
    case NetworkException():
      return 'Reading a receipt needs an internet connection. ${error.message} '
          'Your photo is kept, so you can try again when you are online.';
    case UnauthorizedException():
      return 'Your sign-in has expired. Please sign in again.';
    case NotFoundException():
      return 'This business could not be found for your account.';
    case RateLimitedException():
      if (error.code == 'business_quota_exceeded') {
        return 'This business has used its receipt-reading allowance for today. '
            'Try again tomorrow, or enter the expense by hand.';
      }
      return 'Too many receipts were sent too quickly. Wait a minute and try again.';
    case final ValidationException invalid:
      if (invalid.code == 'image_unsupported') {
        return 'This image could not be read. Try another photo.';
      }
      if (invalid.code == 'receipt_not_processed') {
        return 'The reading service could not process this image. Try a clearer photo.';
      }
      return invalid.fieldMessages()['image'] ?? invalid.message;
    case ServerException():
      switch (error.code) {
        case 'upstream_unavailable':
          return 'The receipt-reading service is unavailable right now. Try again later, or enter the expense by hand.';
        case 'upstream_rejected':
          return 'The receipt-reading service is not set up correctly on the server. Tell the person who runs HisabAI.';
        case 'invalid_response':
          return 'The reading service gave an answer that could not be used. Try again, or enter the expense by hand.';
      }
      return error.message;
    case ForbiddenException():
    case ConflictException():
    case UnexpectedResponseException():
      return error.message;
  }
}
