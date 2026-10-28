import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/storage/token_store.dart';
import 'auth_models.dart';

/// All authentication and business-membership calls to the API.
class AuthRepository {
  AuthRepository({required ApiClient api, required TokenStore tokenStore})
    : _api = api,
      _tokenStore = tokenStore;

  final ApiClient _api;
  final TokenStore _tokenStore;

  static const _deviceName = 'HisabAI Android';

  Future<Session> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final json = await _api.post(
      '/api/v1/auth/register',
      authenticated: false,
      body: {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'device_name': _deviceName,
      },
    );
    await _storeTokenFrom(json);
    return loadSession();
  }

  Future<Session> login({
    required String email,
    required String password,
  }) async {
    final json = await _api.post(
      '/api/v1/auth/login',
      authenticated: false,
      body: {
        'email': email.trim(),
        'password': password,
        'device_name': _deviceName,
      },
    );
    await _storeTokenFrom(json);
    return loadSession();
  }

  /// An authenticated request: proves the stored token works and returns the
  /// user and their businesses.
  Future<Session> loadSession() async {
    final json = await _api.get('/api/v1/me');
    return parseResponse(() => Session.fromJson(json));
  }

  /// Revokes the token on the server, then always forgets it on this device.
  ///
  /// If the server cannot be reached, the user is still signed out locally;
  /// the old token then simply expires on the server (see token lifetime).
  Future<void> logout() async {
    try {
      await _api.post('/api/v1/auth/logout');
    } on NetworkException {
      // Signed out locally anyway.
    } on ServerException {
      // Signed out locally anyway.
    } on UnauthorizedException {
      // Token already invalid on the server: nothing to revoke.
    } finally {
      await _tokenStore.clear();
    }
  }

  Future<void> createBusiness(String name) async {
    await _api.post('/api/v1/businesses', body: {'name': name.trim()});
  }

  Future<void> joinBusiness(String code) async {
    await _api.post('/api/v1/invitations/accept', body: {'code': code.trim()});
  }

  Future<InvitationCode> createInvitation(String businessId) async {
    final json = await _api.post('/api/v1/businesses/$businessId/invitations');
    return parseResponse(() {
      final data = json['data'] as Map<String, dynamic>;
      return InvitationCode(
        code: data['code'] as String,
        expiresAt: DateTime.parse(data['expires_at'] as String),
      );
    });
  }

  Future<void> _storeTokenFrom(Map<String, dynamic> json) async {
    final token = parseResponse(() {
      final data = json['data'] as Map<String, dynamic>;
      return data['token'] as String;
    });
    await _tokenStore.write(token);
  }
}
