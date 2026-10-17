/// Where the real backend is. Passed in at build time, never committed:
///
///   flutter run --dart-define=API_URL=http://192.168.1.42:8000 --dart-define=API_KEY=...
///
/// API_URL is the LAN address of the laptop running uvicorn (`ipconfig`),
/// reachable from the phone on the same network. API_KEY is APP_API_KEY from
/// backend/.env. Without API_URL the app runs on MockRepository.
///
/// The app never holds the database URL or the Gemini key; only the backend
/// does.
class ApiConfig {
  const ApiConfig({required this.baseUrl, required this.apiKey, this.binId = 'bin-001', this.userId = 'demo-user'});

  final String baseUrl;
  final String apiKey;
  final String binId;
  final String userId;

  static const _url = String.fromEnvironment('API_URL');
  static const _key = String.fromEnvironment('API_KEY');
  static const _bin = String.fromEnvironment('BIN_ID', defaultValue: 'bin-001');
  static const _user = String.fromEnvironment('USER_ID', defaultValue: 'demo-user');

  /// True when the app was built with an API_URL.
  static const configured = _url != '';

  static ApiConfig fromEnvironment() =>
      ApiConfig(baseUrl: _url.endsWith('/') ? _url.substring(0, _url.length - 1) : _url, apiKey: _key, binId: _bin, userId: _user);
}
