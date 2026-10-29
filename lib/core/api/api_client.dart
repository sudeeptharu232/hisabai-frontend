import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../storage/token_store.dart';
import 'api_exception.dart';

/// Small JSON-over-HTTP client for the HisabAI API.
///
/// Adds the bearer token to authenticated calls and converts every failure
/// into a typed [ApiException].
class ApiClient {
  ApiClient({
    required this.config,
    required http.Client httpClient,
    required TokenStore tokenStore,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient,
       _tokenStore = tokenStore;

  final ApiConfig config;
  final Duration timeout;
  final http.Client _http;
  final TokenStore _tokenStore;

  /// Called when an *authenticated* request is answered with 401, meaning the
  /// stored token is no longer valid (expired or revoked).
  void Function()? onSessionExpired;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) {
    return _send('GET', path, query: query, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) {
    return _send('POST', path, body: body, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) {
    return _send('PATCH', path, body: body, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    bool authenticated = true,
  }) {
    return _send('DELETE', path, authenticated: authenticated);
  }

  /// POSTs one file as `multipart/form-data`; the server reads it by [fileField].
  ///
  /// Uses the same bearer token and error handling as the JSON methods. [timeout]
  /// replaces the default for this call only (reading a receipt takes the server
  /// several seconds because it waits for Gemini). The file's content type is not
  /// declared: the server detects it from the bytes.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String fileField,
    required List<int> bytes,
    required String filename,
    Duration? timeout,
    bool authenticated = true,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (authenticated) {
      final token = await _tokenStore.read();
      if (token == null) {
        throw const UnauthorizedException('You are not signed in.');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    final request = http.MultipartRequest('POST', config.uri(path))
      ..headers.addAll(headers)
      ..files.add(
        http.MultipartFile.fromBytes(fileField, bytes, filename: filename),
      );

    Future<http.Response> sendIt() async {
      final streamed = await _http.send(request);
      return http.Response.fromStream(streamed);
    }

    final http.Response response;
    try {
      response = await sendIt().timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw const NetworkException('The server took too long to respond.');
    } on SocketException {
      throw const NetworkException(
        'Cannot reach the server. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const NetworkException(
        'Cannot reach the server. Check your connection and try again.',
      );
    }

    return _handle(response, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    required bool authenticated,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    if (authenticated) {
      final token = await _tokenStore.read();
      if (token == null) {
        throw const UnauthorizedException('You are not signed in.');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    final baseUri = config.uri(path);
    final uri = (query == null || query.isEmpty)
        ? baseUri
        : baseUri.replace(queryParameters: query);
    final http.Response response;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      final request = switch (method) {
        'GET' => _http.get(uri, headers: headers),
        'POST' => _http.post(uri, headers: headers, body: encoded),
        'PATCH' => _http.patch(uri, headers: headers, body: encoded),
        'DELETE' => _http.delete(uri, headers: headers),
        _ => throw ArgumentError('Unsupported HTTP method: $method'),
      };
      response = await request.timeout(timeout);
    } on TimeoutException {
      throw const NetworkException('The server took too long to respond.');
    } on SocketException {
      throw const NetworkException(
        'Cannot reach the server. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const NetworkException(
        'Cannot reach the server. Check your connection and try again.',
      );
    }

    return _handle(response, authenticated: authenticated);
  }

  Map<String, dynamic> _handle(
    http.Response response, {
    required bool authenticated,
  }) {
    final status = response.statusCode;
    final json = _decodeObject(response.body);
    final serverMessage = json != null && json['message'] is String
        ? json['message'] as String
        : null;
    final code = json != null && json['code'] is String
        ? json['code'] as String
        : null;

    if (status >= 200 && status < 300) {
      if (json != null) return json;
      if (response.body.trim().isEmpty) return <String, dynamic>{};
      throw const UnexpectedResponseException(
        'The server sent a response this app could not understand.',
      );
    }

    if (status == 401) {
      if (authenticated) onSessionExpired?.call();
      throw UnauthorizedException(
        serverMessage ?? 'Authentication failed.',
        code: code,
      );
    }
    if (status == 403) {
      throw ForbiddenException(
        serverMessage ?? 'You are not allowed to do that.',
        code: code,
      );
    }
    if (status == 404) {
      throw NotFoundException(serverMessage ?? 'Not found.', code: code);
    }
    if (status == 409) {
      throw ConflictException(
        serverMessage ?? 'This conflicts with existing data.',
        code: code,
      );
    }
    if (status == 422) {
      throw ValidationException(
        serverMessage ?? 'Please check the highlighted fields.',
        _parseErrors(json?['errors']),
        code: code,
      );
    }
    if (status == 429) {
      throw RateLimitedException(
        'Too many attempts. Please wait a minute and try again.',
        code: code,
      );
    }
    if (status >= 500) {
      throw ServerException(
        'The server had a problem. Please try again shortly.',
        code: code,
      );
    }
    throw UnexpectedResponseException(
      'Unexpected response (HTTP $status).',
      code: code,
    );
  }

  Map<String, dynamic>? _decodeObject(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, List<String>> _parseErrors(Object? raw) {
    if (raw is! Map<String, dynamic>) return const {};
    return {
      for (final entry in raw.entries)
        entry.key: entry.value is List
            ? (entry.value as List<dynamic>).map((e) => e.toString()).toList()
            : <String>[entry.value.toString()],
    };
  }
}
