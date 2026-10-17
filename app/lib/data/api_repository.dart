import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/advice_rules.dart';
import '../domain/models.dart';
import 'api_config.dart';
import 'calmpost_repository.dart';
import 'food_catalog.dart';

/// The real bin: FastAPI + Tiger Data (backend/README.md).
///
/// How live data gets here: the board prints a reading over USB about once a
/// second, scripts/serial_bridge.py POSTs it to /ingest, the backend stores it
/// in Tiger, and this class polls GET /bins/{id}/live every [pollEvery].
///
/// Rules stay in the app (suggestions, catalog search); the backend supplies
/// readings, trends, the scrap-check verdict (Gemini words, rules decide),
/// the add log and the league.
class ApiRepository implements CalmpostRepository {
  ApiRepository(this.config, {http.Client? client, this.pollEvery = const Duration(seconds: 3)}) : _http = client ?? http.Client();

  final ApiConfig config;
  final Duration pollEvery;
  final http.Client _http;
  BinSnapshot? _last;

  void close() => _http.close();

  Map<String, String> get _headers => {'X-API-Key': config.apiKey, 'Content-Type': 'application/json'};

  Uri _uri(String path, [Map<String, dynamic>? query]) => Uri.parse('${config.baseUrl}$path').replace(queryParameters: query);

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    final res = await _http.get(_uri(path, query), headers: _headers).timeout(const Duration(seconds: 10));
    return _decode('GET $path', res);
  }

  Future<dynamic> _post(String path, Object body, [Map<String, dynamic>? query]) async {
    // Advice can wait on Gemini, so give it longer.
    final res = await _http.post(_uri(path, query), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25));
    return _decode('POST $path', res);
  }

  dynamic _decode(String request, http.Response res) {
    if (res.statusCode >= 400) throw ApiException(request, res.statusCode, res.body);
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  // --- live ------------------------------------------------------------------

  @override
  Stream<BinSnapshot> watchBin() async* {
    while (true) {
      try {
        yield _last = snapshotFromJson(await _get('/bins/${config.binId}/live') as Map<String, dynamic>);
      } catch (e) {
        // Keep polling; the UI keeps the last snapshot and can show the error.
        yield* Stream<BinSnapshot>.error(e);
      }
      await Future<void>.delayed(pollEvery);
    }
  }

  @override
  Future<List<TrendPoint>> trends(Zone zone, Metric metric) async {
    // The backend's series come from the one probe (top layer) and the air
    // sensor. There is no bottom-layer series until a second probe exists.
    if (zone == Zone.bottom && !(_last?.bottomMeasured ?? false)) return const [];
    final name = switch (metric) {
      Metric.moisture => 'moisture',
      Metric.temperature => zone == Zone.air ? 'air_temp' : 'temperature',
      Metric.co2 => 'co2',
    };
    final j = await _get('/bins/${config.binId}/trends', {'hours': '24', 'metrics': name}) as Map<String, dynamic>;
    final series = (j['series'] as List).cast<Map<String, dynamic>>();
    if (series.isEmpty) return const [];
    return [
      for (final p in (series.first['points'] as List).cast<Map<String, dynamic>>())
        if (p['value'] != null) TrendPoint(DateTime.parse(p['bucket'] as String).toLocal(), (p['value'] as num).toDouble()),
    ];
  }

  // --- scrap check and log -------------------------------------------------------

  @override
  Future<Advice> checkItem(FoodItem item) async {
    final j = await _post('/bins/${config.binId}/advice/check', {'item': item.name}) as Map<String, dynamic>;
    return adviceFromJson(item, j);
  }

  @override
  Future<void> logItem(FoodItem item) async {
    try {
      await _post('/bins/${config.binId}/logs', {'item': item.name, 'catalog_id': item.id, 'category': item.category.name, 'action': 'added'});
    } catch (e) {
      // The add already counts on the phone; don't break the sheet over it.
      debugPrint('logItem failed: $e');
    }
  }

  // --- local rules and catalog -----------------------------------------------------

  @override
  Suggestion suggestions(BinSnapshot snapshot) => suggestFor(snapshot, foodById);

  @override
  List<FoodItem> searchFoods(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return foodCatalog;
    return foodCatalog.where((f) => f.name.toLowerCase().contains(q) || f.id.contains(q)).toList();
  }

  @override
  FoodItem? food(String id) => foodById[id];

  /// Replaced by the camera drop-in (AGENT.md 2.4), which goes through the
  /// backend's /drops endpoints.
  @override
  Future<FoodItem> identifyPhoto() => Future.error(UnsupportedError('Photo logging is handled by the camera drop-in'));

  // --- league ------------------------------------------------------------------------

  @override
  Future<List<LeagueMember>> leagueCohort() async {
    try {
      final j = await _get('/leagues/current', {'user_id': config.userId}) as Map<String, dynamic>;
      return [
        for (final m in (j['members'] as List).cast<Map<String, dynamic>>())
          if (m['is_you'] != true)
            LeagueMember(
              name: m['display_name'] as String,
              xp: (m['xp'] as num).toInt(),
              colorIndex: (m['color_index'] as num?)?.toInt() ?? 0,
              isFriend: m['is_friend'] == true,
              streak: (m['streak'] as num?)?.toInt() ?? 0,
            ),
      ];
    } on ApiException catch (e) {
      // Not in a league yet (or none this week): the table shows just you.
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }
}

class ApiException implements Exception {
  ApiException(this.request, this.statusCode, this.body);
  final String request;
  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($request -> $statusCode): $body';
}

// --- JSON -> domain (public for tests) ----------------------------------------------

double? _d(Object? v) => (v as num?)?.toDouble();

Stage _stage(Object? v) => Stage.values.firstWhere((s) => s.name == v, orElse: () => Stage.started);

/// GET /bins/{id}/live -> BinSnapshot. An unmeasured bottom layer gets
/// placeholder numbers that the UI never shows (bottomMeasured is false).
BinSnapshot snapshotFromJson(Map<String, dynamic> j) {
  final layers = {for (final l in (j['layers'] as List).cast<Map<String, dynamic>>()) l['layer'] as String: l};
  final top = layers['top'] ?? const <String, dynamic>{};
  final bottom = layers['bottom'] ?? const <String, dynamic>{};
  final air = (j['air'] as Map<String, dynamic>?) ?? const {};
  final ambient = _d(air['ambient_temp_c']) ?? 21.0;
  final topMoisture = _d(top['moisture_pct']) ?? 0;
  final topTemp = _d(top['temp_c']) ?? ambient;
  final bottomMeasured = bottom['measured'] == true && bottom['moisture_pct'] != null;
  return BinSnapshot(
    time: DateTime.parse(j['time'] as String).toLocal(),
    topMoisture: topMoisture,
    topTemp: topTemp,
    bottomMoisture: bottomMeasured ? _d(bottom['moisture_pct'])! : topMoisture,
    bottomTemp: bottomMeasured ? (_d(bottom['temp_c']) ?? ambient) : ambient,
    co2: _d(air['co2_ppm']) ?? 0,
    ambientTemp: ambient,
    co2SlopePerDay: _d(air['co2_slope_per_day']) ?? 0,
    greens7d: _d(j['greens_7d']) ?? 0,
    browns7d: _d(j['browns_7d']) ?? 0,
    topStage: _stage(top['stage']),
    bottomStage: _stage(bottom['stage']),
    healthyHoursToday: _d(j['healthy_hours_today']) ?? 0,
    bottomMeasured: bottomMeasured,
    stale: j['stale'] == true,
  );
}

/// POST /bins/{id}/advice/check -> Advice. pair_with names are matched to the
/// catalog; anything it doesn't know is dropped.
Advice adviceFromJson(FoodItem item, Map<String, dynamic> j) {
  FoodItem? match(String name) {
    final n = name.toLowerCase().trim();
    return foodCatalog.where((f) => f.name.toLowerCase() == n || f.id == n).firstOrNull ??
        foodCatalog.where((f) => f.name.toLowerCase().contains(n) || n.contains(f.name.toLowerCase())).firstOrNull;
  }

  final pair = <FoodItem>[];
  for (final name in ((j['pair_with'] as List?) ?? const []).cast<String>()) {
    final f = match(name);
    if (f != null && f.id != item.id && !pair.contains(f)) pair.add(f);
  }
  return Advice(
    item: item,
    verdict: Verdict.values.firstWhere((v) => v.name == j['verdict'], orElse: () => Verdict.careful),
    headline: (j['headline'] as String?) ?? '',
    reason: (j['reason'] as String?) ?? '',
    pairWith: pair,
  );
}
