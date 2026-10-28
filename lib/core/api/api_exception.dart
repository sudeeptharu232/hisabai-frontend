/// Typed API failures. Every message is safe to show to the user.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// No connection, DNS failure, or timeout.
final class NetworkException extends ApiException {
  const NetworkException(super.message);
}

/// 401: not signed in, or the token is invalid/expired/revoked, or bad credentials.
final class UnauthorizedException extends ApiException {
  const UnauthorizedException(super.message);
}

/// 403: signed in but not allowed (e.g. a member doing an owner-only action).
final class ForbiddenException extends ApiException {
  const ForbiddenException(super.message);
}

/// 404: also what the API returns for a business the user does not belong to.
final class NotFoundException extends ApiException {
  const NotFoundException(super.message);
}

/// 409: e.g. the user already belongs to a business.
final class ConflictException extends ApiException {
  const ConflictException(super.message);
}

/// 422: field-level validation errors from the server.
final class ValidationException extends ApiException {
  const ValidationException(super.message, this.errors);

  final Map<String, List<String>> errors;

  /// The first server message per field, for showing under form fields.
  Map<String, String> fieldMessages() => {
    for (final entry in errors.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value.first,
  };
}

/// 429: too many attempts.
final class RateLimitedException extends ApiException {
  const RateLimitedException(super.message);
}

/// 5xx.
final class ServerException extends ApiException {
  const ServerException(super.message);
}

/// The server answered, but not in the shape this app expects.
final class UnexpectedResponseException extends ApiException {
  const UnexpectedResponseException(super.message);
}
