// Dart client for the Calmpost backend.
//
// Methods mirror CalmpostRepository, so wiring ApiRepository to this is
// mechanical. Drop into lib/data/ and add `http` to pubspec.yaml.
//
//   final api = CalmpostApi(
//     // LAN IP of the laptop running uvicorn, on the same network as the
//     // phone. Find it with `ipconfig` / `ipconfig getifaddr en0`.
//     baseUrl: 'http://192.168.1.42:8000',
//     apiKey: '<APP_API_KEY from backend/.env>',
//   );
//
// The app never talks to Tiger Data directly -- the backend holds the
// database and Gemini keys. Never put either in the Flutter app.

import 'dart:convert';
import 'package:http/http.dart' as http;

class CalmpostApi {
  CalmpostApi({
    required this.baseUrl,
    required this.apiKey,
    this.binId = 'bin-001',
    this.userId = 'demo-user',
  });

  final String baseUrl;
  final String apiKey;
  final String binId;
  final String userId;

  Map<String, String> get _headers => {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final res = await http.get(_uri(path, query), headers: _headers);
    if (res.statusCode >= 400) {
      throw CalmpostApiException('GET $path', res.statusCode, res.body);
    }
    return jsonDecode(res.body);
  }

  Future<dynamic> _post(String path, [Object? body, Map<String, String>? query]) async {
    final res = await http.post(
      _uri(path, query),
      headers: _headers,
      body: body == null ? null : jsonEncode(body),
    );
    if (res.statusCode >= 400) {
      throw CalmpostApiException('POST $path', res.statusCode, res.body);
    }
    return jsonDecode(res.body);
  }

  // --- live & trends -------------------------------------------------------

  /// Current state of both layers plus the air gap.
  ///
  /// Read `layers[i].measured` before showing a layer: the current build has
  /// one probe, so the bottom layer is unmeasured and must render as unknown
  /// rather than 0. `notes` carries plain-language caveats (uncalibrated
  /// probe, unhealthy CO2 sensor, bin offline) worth surfacing in the UI.
  ///
  /// `health_components` holds the four terms for domain/health_score.dart --
  /// the app owns the formula, the backend just supplies the inputs.
  Future<Map<String, dynamic>> live() async =>
      await _get('/bins/$binId/live') as Map<String, dynamic>;

  /// Chart series, gap-filled. Buckets are 15m up to a week, then daily.
  /// metrics: moisture_pct, probe_temp_c, co2_ppm, air_temp_c, air_humidity_pct
  Future<Map<String, dynamic>> trends({
    int hours = 24,
    List<String> metrics = const ['moisture_pct', 'probe_temp_c', 'co2_ppm'],
  }) async {
    // FastAPI takes a repeated list param (?metrics=a&metrics=b), which
    // Uri's queryParameters map cannot express, so build the query directly.
    final uri = Uri.parse('$baseUrl/bins/$binId/trends').replace(
      queryParameters: <String, dynamic>{
        'hours': '$hours',
        'metrics': metrics,
      },
    );
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode >= 400) {
      throw CalmpostApiException('GET /trends', res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // --- the demo moment -----------------------------------------------------

  /// Ask whether one item should go in right now.
  ///
  /// Returns verdict ('add' | 'add_with_browns' | 'avoid'), reason,
  /// suggest_add, suggest_avoid, balance, stage_top, stage_bottom,
  /// bottom_ready, tip -- and `input_snapshot`, the sensor state the answer
  /// was based on. Show that snapshot to prove the same scrap got a
  /// different answer because the bin changed.
  ///
  /// Pass refresh: true after changing the bin's state on stage, so the
  /// cached answer is bypassed.
  Future<Map<String, dynamic>> checkItem(String item, {bool refresh = false}) async =>
      await _post(
        '/bins/$binId/advice/check',
        {'item': item},
        refresh ? {'refresh': 'true'} : null,
      ) as Map<String, dynamic>;

  /// Whole-bin advice for Home's "Wren suggests" card.
  Future<Map<String, dynamic>> advice({bool refresh = false}) async =>
      await _get('/bins/$binId/advice', refresh ? {'refresh': 'true'} : null)
          as Map<String, dynamic>;

  // --- log -----------------------------------------------------------------

  /// Record an add. A plain log earns 0 XP by design; pass wasAdvised when
  /// the user followed a suggestion (+15).
  Future<Map<String, dynamic>> logAdd({
    required String item,
    String category = 'unknown',
    int? quantityG,
    bool wasAdvised = false,
    int? adviceId,
  }) async =>
      await _post('/bins/$binId/logs', {
        'item': item,
        'category': category,
        'action': 'added',
        'quantity_g': quantityG,
        'was_advised': wasAdvised,
        'advice_id': adviceId,
      }) as Map<String, dynamic>;

  /// Record that the user trusted an 'avoid' verdict and did NOT add it (+5).
  Future<Map<String, dynamic>> logSkip({
    required String item,
    int? adviceId,
  }) async =>
      await _post('/bins/$binId/logs', {
        'item': item,
        'action': 'skipped',
        'was_advised': true,
        'advice_id': adviceId,
      }) as Map<String, dynamic>;

  Future<List<dynamic>> recentLog({int limit = 50}) async =>
      await _get('/bins/$binId/logs', {'limit': '$limit'}) as List<dynamic>;

  // --- game ----------------------------------------------------------------

  /// Level, XP, Seeds, streak, lid locks, impact stats and achievements.
  Future<Map<String, dynamic>> gameState() async =>
      await _get('/users/$userId/game') as Map<String, dynamic>;

  /// Today's three care-based quests with live progress.
  Future<Map<String, dynamic>> questsToday() async =>
      await _get('/quests/today', {'user_id': userId}) as Map<String, dynamic>;

  /// This week's league cohort, ranked, with promotion/demotion zones.
  Future<Map<String, dynamic>> currentLeague() async =>
      await _get('/leagues/current', {'user_id': userId}) as Map<String, dynamic>;

  /// Call when the user actually opens the bin screen -- ticks the streak.
  /// Merely polling live() deliberately does not.
  Future<Map<String, dynamic>> checkIn() async =>
      await _post('/users/$userId/check-in') as Map<String, dynamic>;

  /// Harvest a layer (+100 XP). `was_ready` reports whether the sensors
  /// agreed, so the celebration can stay honest.
  Future<Map<String, dynamic>> harvest({
    String layer = 'bottom',
    int? yieldG,
  }) async =>
      await _post('/bins/$binId/harvest', {'layer': layer, 'yield_g': yieldG})
          as Map<String, dynamic>;

  // --- setup ---------------------------------------------------------------

  /// Calibrate the moisture probe: raw ADC in air (dry) and in water (wet).
  /// Until this is done, moisture percentages are rough guesses and
  /// live()'s `moisture_calibrated` is false.
  Future<Map<String, dynamic>> calibrate({
    required int rawDry,
    required int rawWet,
    bool backfill = true,
  }) async =>
      await _post('/bins/$binId/calibration', {
        'moisture_raw_dry': rawDry,
        'moisture_raw_wet': rawWet,
        'backfill': backfill,
      }) as Map<String, dynamic>;
}

class CalmpostApiException implements Exception {
  CalmpostApiException(this.request, this.statusCode, this.body);

  final String request;
  final int statusCode;
  final String body;

  @override
  String toString() => 'CalmpostApiException($request -> $statusCode): $body';
}
