import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/storage/token_store.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

enum AuthStatus {
  /// Checking for a stored token at app start.
  restoring,

  /// A token exists but the server could not be reached to verify it.
  restoreFailed,

  unauthenticated,

  authenticated,
}

/// Holds the authentication state of the whole app.
class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required ApiClient api,
    required TokenStore tokenStore,
  }) : _repository = repository,
       _tokenStore = tokenStore {
    // If any authenticated call is rejected with 401, the session is over.
    api.onSessionExpired = _handleSessionExpired;
  }

  final AuthRepository _repository;
  final TokenStore _tokenStore;

  AuthStatus _status = AuthStatus.restoring;
  Session? _session;
  DateTime? _lastVerifiedAt;
  String? _restoreError;

  AuthStatus get status => _status;

  Session? get session => _session;

  /// When the server last confirmed the token (shown on the home screen).
  DateTime? get lastVerifiedAt => _lastVerifiedAt;

  String? get restoreError => _restoreError;

  /// Called once at app start.
  Future<void> restore() async {
    _status = AuthStatus.restoring;
    _restoreError = null;
    notifyListeners();

    final token = await _tokenStore.read();
    if (token == null) {
      _setUnauthenticated();
      return;
    }

    try {
      _setAuthenticated(await _repository.loadSession());
    } on UnauthorizedException {
      await _tokenStore.clear();
      _setUnauthenticated();
    } on ApiException catch (e) {
      // Offline or server trouble: keep the token and let the user retry.
      _restoreError = e.message;
      _status = AuthStatus.restoreFailed;
      notifyListeners();
    }
  }

  Future<void> login({required String email, required String password}) async {
    _setAuthenticated(
      await _repository.login(email: email, password: password),
    );
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    _setAuthenticated(
      await _repository.register(name: name, email: email, password: password),
    );
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } finally {
      // Whatever the server said, this device is signed out.
      _setUnauthenticated();
    }
  }

  /// Re-fetches the profile with the stored token (an authenticated request).
  Future<void> refresh() async {
    _setAuthenticated(await _repository.loadSession());
  }

  Future<void> createBusiness(String name) async {
    await _repository.createBusiness(name);
    await refresh();
  }

  Future<void> joinBusiness(String code) async {
    await _repository.joinBusiness(code);
    await refresh();
  }

  Future<InvitationCode> createInvitation(String businessId) {
    return _repository.createInvitation(businessId);
  }

  void _setAuthenticated(Session session) {
    _session = session;
    _lastVerifiedAt = DateTime.now();
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  void _setUnauthenticated() {
    _session = null;
    _lastVerifiedAt = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _handleSessionExpired() {
    unawaited(_tokenStore.clear());
    _setUnauthenticated();
  }
}
