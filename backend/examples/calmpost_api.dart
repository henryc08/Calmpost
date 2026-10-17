// Minimal Dart client for the Calmpost backend.
// Drop into the Flutter app's lib/services/ and add `http` to pubspec.yaml.
//
//   final api = CalmpostApi(
//     baseUrl: 'http://192.168.1.42:8000',  // laptop's LAN IP during the demo
//     apiKey: 'dev-change-me',              // APP_API_KEY from the backend .env
//   );
//   final status = await api.latest('bin-01');
//   final advice = await api.advice('bin-01');

import 'dart:convert';
import 'package:http/http.dart' as http;

class CalmpostApi {
  CalmpostApi({required this.baseUrl, required this.apiKey});

  final String baseUrl;
  final String apiKey;

  Map<String, String> get _headers => {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      };

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode >= 400) {
      throw Exception('GET $path failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body);
  }

  /// Current reading for each zone, plus a dry/ok/wet flag per layer.
  Future<Map<String, dynamic>> latest(String deviceId) async =>
      await _get('/v1/devices/$deviceId/latest') as Map<String, dynamic>;

  /// Hourly buckets for a trend chart. zone is 'top', 'bottom' or 'airgap'.
  Future<List<dynamic>> history(
    String deviceId, {
    String zone = 'top',
    int hours = 24,
  }) async {
    final body = await _get(
      '/v1/devices/$deviceId/history',
      {'zone': zone, 'hours': '$hours'},
    ) as Map<String, dynamic>;
    return body['points'] as List<dynamic>;
  }

  /// Gemini's recommendations. Pass refresh: true after the bin state changes
  /// so the demo shows a new answer instead of the cached one.
  Future<Map<String, dynamic>> advice(
    String deviceId, {
    bool refresh = false,
  }) async =>
      await _get(
        '/v1/devices/$deviceId/advice',
        refresh ? {'refresh': 'true'} : null,
      ) as Map<String, dynamic>;

  /// Log something the user added. Returns the entry plus points awarded.
  Future<Map<String, dynamic>> logAdd({
    required String deviceId,
    required String item,
    String zone = 'top',
    int? quantityG,
    bool wasAdvised = false,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/v1/log'),
      headers: _headers,
      body: jsonEncode({
        'device_id': deviceId,
        'item': item,
        'zone': zone,
        'quantity_g': quantityG,
        'was_advised': wasAdvised,
      }),
    );
    if (res.statusCode >= 400) {
      throw Exception('POST /v1/log failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> recentLog(String deviceId, {int limit = 50}) async =>
      await _get('/v1/devices/$deviceId/log', {'limit': '$limit'})
          as List<dynamic>;

  /// Total points, streak length and this week's log count for the home screen.
  Future<Map<String, dynamic>> points(String userId) async =>
      await _get('/v1/users/$userId/points') as Map<String, dynamic>;
}
