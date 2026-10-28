/// Where the HisabAI API lives.
///
/// Override at build/run time without editing code:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
///
/// The default targets the Android emulator, where the host machine's
/// localhost is reachable as 10.0.2.2. A physical phone needs the host's
/// LAN IP instead (see docs/SETUP.md). No secrets belong in this file.
class ApiConfig {
  const ApiConfig({required this.baseUrl});

  static const ApiConfig fromEnvironment = ApiConfig(
    baseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    ),
  );

  final String baseUrl;

  /// Builds an absolute URI for an API path such as `/api/v1/health`.
  Uri uri(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }
}
