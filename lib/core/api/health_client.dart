import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

enum HealthFailureReason { network, timeout, badResponse, httpError }

/// Outcome of a health check. Exhaustively switchable.
sealed class HealthResult {
  const HealthResult();
}

final class HealthOk extends HealthResult {
  const HealthOk({this.serverTime});

  final String? serverTime;
}

/// The API answered but reported that a dependency (the database) is down.
final class HealthDegraded extends HealthResult {
  const HealthDegraded({required this.databaseStatus});

  final String databaseStatus;
}

final class HealthFailure extends HealthResult {
  const HealthFailure({required this.reason, required this.message});

  final HealthFailureReason reason;

  /// A user-presentable explanation. Never contains secrets.
  final String message;
}

class HealthClient {
  HealthClient({
    required this.config,
    required http.Client httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _http = httpClient;

  final ApiConfig config;
  final Duration timeout;
  final http.Client _http;

  Future<HealthResult> check() async {
    final uri = config.uri('/api/v1/health');
    try {
      final response = await _http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
      final body = _decodeObject(response.body);

      if (response.statusCode == 200 && body?['status'] == 'ok') {
        return HealthOk(serverTime: body?['time'] as String?);
      }
      if (response.statusCode == 503 && body?['status'] == 'degraded') {
        final checks = body?['checks'];
        final database = checks is Map<String, dynamic>
            ? checks['database']?.toString()
            : null;
        return HealthDegraded(databaseStatus: database ?? 'unknown');
      }
      if (body == null) {
        return HealthFailure(
          reason: HealthFailureReason.badResponse,
          message:
              'The server sent an unexpected response '
              '(HTTP ${response.statusCode}).',
        );
      }
      return HealthFailure(
        reason: HealthFailureReason.httpError,
        message: 'The server returned HTTP ${response.statusCode}.',
      );
    } on TimeoutException {
      return HealthFailure(
        reason: HealthFailureReason.timeout,
        message:
            'No answer from ${config.baseUrl} within '
            '${timeout.inSeconds} seconds.',
      );
    } on SocketException {
      return _networkFailure();
    } on http.ClientException {
      return _networkFailure();
    }
  }

  HealthFailure _networkFailure() => HealthFailure(
    reason: HealthFailureReason.network,
    message:
        'Cannot reach the server at ${config.baseUrl}. '
        'Check that the API is running and that this device can reach it.',
  );

  Map<String, dynamic>? _decodeObject(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
