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
  ApiRepository(this.config, {http.Client? client, this.pollEvery = const Duration(seconds: 3), this.dropPollEvery = const Duration(seconds: 1)}) : _http = client ?? http.Client();

  final ApiConfig config;
  final Duration pollEvery;

  /// How often [watchDrops] asks for pending detections. The backend's own
  /// SSE endpoint re-reads its table once a second, so polling at the same
  /// rate costs the same latency.
  final Duration dropPollEvery;
  final http.Client _http;

  void close() => _http.close();

  Map<String, String> get _headers => {'X-API-Key': config.apiKey, 'Content-Type': 'application/json', if (config.token != null) 'Authorization': 'Bearer ${config.token}'};

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
        yield snapshotFromJson(await _get('/bins/${config.binId}/live') as Map<String, dynamic>);
      } catch (e) {
        // Keep polling; the UI keeps the last snapshot and can show the error.
        yield* Stream<BinSnapshot>.error(e);
      }
      await Future<void>.delayed(pollEvery);
    }
  }

  @override
  Future<List<TrendPoint>> trends(Zone zone, Metric metric) async {
    // The bottom layer now reports live (second probe), but the continuous
    // aggregates behind /trends still carry probe 1 only, so asking for a
    // bottom series would chart the TOP probe's history under a bottom label.
    // Empty until readings_15m/readings_1d gain the second probe -- see
    // backend/sql/007_second_probe.sql.
    if (zone == Zone.bottom) return const [];
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

  /// Replaced by the camera drop-in (AGENTS.md 2.4), which goes through the
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

  // --- camera drop-in ----------------------------------------------------------------

  @override
  Future<DropSession> startDropSession() async {
    final j = await _post('/bins/${config.binId}/drops/session', const <String, dynamic>{}) as Map<String, dynamic>;
    return DropSession(
      id: j['session_id'] as String,
      expiresAt: DateTime.parse(j['expires_at'] as String).toLocal(),
    );
  }

  /// Polls the pending list rather than reading the SSE stream: the stream
  /// handler re-queries once a second anyway, so this is the same latency
  /// without holding a long-lived response open, which is the part that
  /// breaks on a flaky hotspot and behind proxies on web.
  @override
  Stream<List<CameraDrop>> watchDrops() async* {
    while (true) {
      try {
        final rows = (await _get('/bins/${config.binId}/drops/pending') as List).cast<Map<String, dynamic>>();
        yield [for (final r in rows) dropFromJson(r)];
      } on Exception {
        // A dropped request must not kill the watch; the next tick retries.
      }
      await Future<void>.delayed(dropPollEvery);
    }
  }

  @override
  Future<DropResult> confirmDrop(int dropId, List<DropConfirmation> items) async {
    final j = await _post('/drops/$dropId/confirm', {
      'items': [
        for (final i in items)
          {
            'label': i.label,
            'catalog_id': i.catalogId,
            // The backend overrides this by its own rules; sending 'unknown'
            // lets it decide rather than asserting a category we guessed.
            'category': i.category?.name ?? 'unknown',
            if (i.amount != null) 'amount': i.amount,
            'removed': i.removed,
            'was_advised': i.wasAdvised,
            if (i.adviceId != null) 'advice_id': i.adviceId,
          },
      ],
    }) as Map<String, dynamic>;

    final verdicts = <Advice>[];
    var xp = 0;
    for (final row in ((j['items'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final log = (row['log'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      xp += (log['xp_awarded'] as num?)?.toInt() ?? 0;
      final verdict = row['verdict'] as Map<String, dynamic>?;
      // No verdict for a removed item, and none when the bin has no readings
      // yet; the add is still logged, so this is not an error.
      if (verdict == null) continue;
      final item = foodForLabel((log['item'] as String?) ?? '', log['catalog_id'] as String?);
      if (item != null) verdicts.add(adviceFromJson(item, verdict));
    }
    return DropResult(
      dropId: (j['drop_id'] as num?)?.toInt() ?? dropId,
      corrected: j['corrected'] == true,
      verdicts: verdicts,
      xpAwarded: xp,
    );
  }

  @override
  Future<void> dismissDrop(int dropId) => _post('/drops/$dropId/dismiss', const <String, dynamic>{});

  @override
  Future<CameraDrop> submitPhoto(Uint8List jpeg) async {
    final j = await _post('/bins/${config.binId}/drops/photo', {
      'image_jpeg_b64': base64Encode(jpeg),
    }) as Map<String, dynamic>;
    return dropFromJson(j);
  }

  // --- Trunc -------------------------------------------------------------------------

  @override
  Future<TruncReply> askTrunc(
    String message, {
    List<TruncTurn> history = const [],
    bool includePhotos = true,
  }) async {
    final j = await _post('/bins/${config.binId}/chat', {
      'message': message,
      'history': [
        for (final t in history) {'role': t.role.name, 'text': t.text},
      ],
      'include_photos': includePhotos,
    }) as Map<String, dynamic>;
    return truncReplyFromJson(j);
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

/// Resolves a backend label to a catalog entry: catalog id first, then an
/// exact name, then a loose contains-match. Null for something the catalog
/// has never heard of, which the UI has to let the user name.
FoodItem? foodForLabel(String label, [String? catalogId]) {
  if (catalogId != null && catalogId != 'unknown') {
    final byId = foodById[catalogId];
    if (byId != null) return byId;
  }
  final n = label.toLowerCase().trim();
  if (n.isEmpty) return null;
  return foodCatalog.where((f) => f.name.toLowerCase() == n || f.id == n).firstOrNull ??
      foodCatalog.where((f) => f.name.toLowerCase().contains(n) || n.contains(f.name.toLowerCase())).firstOrNull;
}

/// GET /bins/{id}/drops/pending (and each `drop` SSE event) -> CameraDrop.
CameraDrop dropFromJson(Map<String, dynamic> j) {
  final guesses = <DropGuess>[];
  for (final g in ((j['items'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
    final label = (g['label'] as String?) ?? '';
    final catalogId = (g['catalog_id'] as String?) ?? 'unknown';
    guesses.add(DropGuess(
      label: label,
      catalogId: catalogId,
      confidence: _d(g['confidence']) ?? 0,
      item: foodForLabel(label, catalogId),
      category: FoodCategory.values.where((c) => c.name == g['category']).firstOrNull,
      amount: g['amount'] as String?,
      estGrams: _d(g['est_grams']),
      box: (g['box_2d'] as List?)?.cast<num>().map((n) => n.toInt()).toList(),
    ));
  }
  final thumb = (j['thumbnail_jpeg_b64'] as String?) ?? '';
  return CameraDrop(
    id: (j['id'] as num).toInt(),
    binId: (j['bin_id'] as String?) ?? '',
    sessionId: (j['session_id'] as String?) ?? '',
    time: DateTime.parse(j['time'] as String).toLocal(),
    status: DropStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => DropStatus.pending),
    source: (j['source'] as String?) ?? 'camera',
    guesses: guesses,
    geminiOk: j['gemini_ok'] == true,
    latencyMs: (j['latency_ms'] as num?)?.toInt() ?? 0,
    model: (j['model'] as String?) ?? '',
    error: j['error'] as String?,
    thumbnailJpeg: thumb.isEmpty ? null : base64Decode(thumb),
  );
}

/// POST /bins/{id}/chat -> TruncReply.
TruncReply truncReplyFromJson(Map<String, dynamic> j) {
  final ctx = (j['context'] as Map<String, dynamic>?) ?? const {};
  final at = ctx['readings_at'] as String?;
  return TruncReply(
    reply: (j['reply'] as String?) ?? '',
    model: (j['model'] as String?) ?? '',
    // Absent means on topic: only an off-topic answer sets it false.
    onTopic: j['on_topic'] != false,
    usedReadings: j['used_readings'] == true,
    context: TruncContext(
      // Null when the bin has never reported, which is not an error: a general
      // question does not need a reading.
      readingsAt: at == null ? null : DateTime.tryParse(at)?.toLocal(),
      recentAdds: (ctx['recent_adds'] as num?)?.toInt() ?? 0,
      photos: (ctx['photos'] as num?)?.toInt() ?? 0,
    ),
  );
}
