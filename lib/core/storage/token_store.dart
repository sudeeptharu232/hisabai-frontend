import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the API bearer token lives between app launches.
abstract interface class TokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> clear();
}

/// Stores the token with flutter_secure_storage (Android Keystore-backed
/// EncryptedSharedPreferences). The token is never written to plain
/// SharedPreferences, logs, or source control.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _key = 'hisabai_api_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } on Exception {
      // Unreadable data (e.g. Keystore reset): treat as signed out and remove it.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } on Exception {
      // Nothing more can be done; the token is unreadable anyway.
    }
  }
}

/// For tests only.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
