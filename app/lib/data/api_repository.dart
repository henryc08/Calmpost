import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:http/http.dart' as http;

import '../domain/advice_rules.dart';
import '../domain/drop.dart';
import '../domain/models.dart';
import '../domain/inventory.dart';
import '../domain/drop_history.dart';
import '../domain/calibration.dart';
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
  ApiRepository(this.config, {http.Client? client, this.pollEvery = const Duration(seconds: 3), this.dropPollEvery = const Duration(seconds: 1)})
    : _http = client ?? http.Client();

  @override
  Future<CompostInventory> inventory({String period = 'all'}) async =>
      CompostInventory.fromJson(await _get('/bins/${config.binId}/inventory', {'period': period}) as Map<String, dynamic>);

  final ApiConfig config;
  @override
  Future<CalibrationResult> calibrateProbe({required int probe, required int dry, required int wet, bool backfill = false}) async {
    final error = calibrationError(probe, dry, wet);
    if (error != null) throw ArgumentError(error);
    return CalibrationResult.fromJson(
      await _post('/bins/${config.binId}/calibration', {'probe': probe, 'moisture_raw_dry': dry, 'moisture_raw_wet': wet, 'backfill': backfill})
          as Map<String, dynamic>,
    );
  }

  @override
  Future<DropHistoryPage> dropHistory({String? before, int limit = 20}) async =>
      DropHistoryPage.fromJson(await _get('/bins/${config.binId}/drops/history', {'limit': '$limit', 'before': ?before}) as Map<String, dynamic>);

  @override
  Future<Uint8List?> dropPhoto(int id) async {
    final path = '/drops/$id/photo';
    final res = await _http.get(_uri(path), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw ApiException('GET $path', res.statusCode, 'Photo unavailable');
    return res.bodyBytes;
  }

  final Duration pollEvery;

  /// How often the drop sheet asks whether the camera saw something.
  final Duration dropPollEvery;
  final http.Client _http;
  List<int> _crateIds = [];

  @override
  // Both player sessions and legacy demo accounts use server-owned progress.
  bool get serverGame => true;

  @override
  Future<Map<String, dynamic>> loadGame() async {
    final user = '/users/${config.userId}';
    // Profile settles earned rewards before the dependent reads.
    final profile = await _get('$user/game');
    final data = await Future.wait([
      _get('$user/rewards'),
      _get('$user/collection'),
      _get('/quests/today', {'user_id': config.userId}),
      config.binId.isEmpty ? Future<dynamic>.value(<dynamic>[]) : _get('/bins/${config.binId}/logs'),
    ]);
    Map<String, dynamic>? league;
    try {
      league = await _get('/leagues/current', {'user_id': config.userId});
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    _crateIds = [for (final c in data[0]['crates']) c['id'] as int];
    return {'profile': profile, 'rewards': data[0], 'collection': data[1], 'quests': data[2], 'logs': data[3], 'league': league};
  }

  @override
  Future<Map<String, dynamic>> gameAction(String action, Map<String, dynamic> args) async {
    final user = '/users/${config.userId}';
    final path = switch (action) {
      'check-in' => config.token == null ? '$user/check-in' : '/social/check-in',
      'quest' => '/quests/${args['id']}/claim',
      'daily' => '$user/daily-goal/${args['index']}/claim',
      'level' => '$user/levels/${args['level']}/claim',
      'crate' => '$user/crates/${_crateIds[args['index'] as int]}/open',
      'pull' => '$user/gacha/pull',
      'equip' => '$user/equip',
      'lid-lock' => '$user/lid-locks/buy',
      _ => throw ArgumentError('Unknown game action'),
    };
    return await _post(path, args, action == 'quest' ? {'user_id': config.userId} : null) as Map<String, dynamic>;
  }

  @override
  Future<void> cancelDropSession(DropSession session) async {
    await _post('/bins/${config.binId}/drops/session/${session.id}/close', {'reason': 'cancelled'});
  }

  @override
  Future<Drop?> pendingDrop() async {
    final pending = await _get('/bins/${config.binId}/drops/pending') as List;
    return pending.isEmpty ? null : reviewedDropFromJson(pending.first as Map<String, dynamic>);
  }

  void close() => _http.close();

  Map<String, String> get _headers => {
    'X-API-Key': config.apiKey,
    'Content-Type': 'application/json',
    if (config.token != null) 'Authorization': 'Bearer ${config.token}',
  };

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
    if (res.statusCode >= 400) {
      throw ApiException(request, res.statusCode, res.body);
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  // --- live ------------------------------------------------------------------

  @override
  Stream<BinSnapshot> watchBin() async* {
    if (config.binId.isEmpty) {
      throw StateError('Connect your bin in Social to see live readings.');
    }
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
    // One row carries both probes, so the layer picks the series rather than
    // being a parameter: moisture is the top probe, moisture_2 the bottom one
    // (008_bottom_trends.sql). The bottom layer used to return nothing here,
    // because asking for 'moisture' would have charted the TOP probe's
    // history under a bottom label.
    //
    // temperature_2 exists for symmetry but has no data yet: the second probe
    // measures moisture only, so probe_temp_c_2 is null in every reading. The
    // series comes back empty, which the chart already handles.
    final bottom = zone == Zone.bottom;
    final name = switch (metric) {
      Metric.moisture => bottom ? 'moisture_2' : 'moisture',
      Metric.temperature => zone == Zone.air ? 'air_temp' : (bottom ? 'temperature_2' : 'temperature'),
      Metric.co2 => 'co2',
    };
    final j =
        await _get('/bins/${config.binId}/trends', {'hours': '24', 'metrics': name, 'layer': zone == Zone.bottom ? 'bottom' : 'top'}) as Map<String, dynamic>;
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
  Future<int?> logItem(FoodItem item, {bool added = true, double? quantityG, int? pieceCount, String? requestId, bool wasAdvised = false}) async {
    final j =
        await _post('/bins/${config.binId}/logs', {
              'item': item.name,
              'catalog_id': item.id,
              'category': item.category.name,
              'action': added ? 'added' : 'skipped',
              'quantity_g': (quantityG ?? item.grams).round(),
              'piece_count': ?pieceCount,
              'request_id': requestId,
              'was_advised': wasAdvised,
            })
            as Map<String, dynamic>;
    return (j['xp_awarded'] as num?)?.toInt() ?? 0;
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

  // --- camera drop-in -----------------------------------------------------------------
  //
  // vision/ watches the bin while a session is armed and reports what it saw;
  // the backend keeps it pending until the user confirms it here.

  @override
  Stream<DropEvent> watchDrop(DropSession session) async* {
    var reportedButMissing = false;
    while (true) {
      final pending = (await _get('/bins/${config.binId}/drops/pending') as List).cast<Map<String, dynamic>>();
      final mine = pending.where((d) => d['session_id'] == session.id).firstOrNull;
      if (mine != null) {
        yield DropSeen(reviewedDropFromJson(mine));
        return;
      }
      final st = await _get('/bins/${config.binId}/drops/sessions/${session.id}') as Map<String, dynamic>;
      if (st['open'] != true) {
        // 'reported' between our two reads: look at pending once more.
        if (st['close_reason'] == 'reported' && !reportedButMissing) {
          reportedButMissing = true;
          continue;
        }
        yield const DropNothing();
        return;
      }
      await Future<void>.delayed(dropPollEvery);
    }
  }

  @override
  Future<List<Advice>> confirmReviewedDrop(Drop drop, List<DropLine> lines, {Set<String> advisedIds = const {}}) async {
    final j =
        await _post('/drops/${drop.id}/confirm', {
              'items': [
                for (final l in lines)
                  {
                    'label': l.item.name,
                    'catalog_id': l.isCustom ? 'unknown' : l.item.id,
                    'category': l.item.category.name,
                    'amount': l.amount.name,
                    'piece_count': l.pieceCount,
                    'quantity_g': l.grams.round(),
                    'removed': l.removed,
                    'was_advised': advisedIds.contains(l.item.id),
                  },
              ],
            })
            as Map<String, dynamic>;
    final items = (j['items'] as List).cast<Map<String, dynamic>>();
    return [
      for (final (i, l) in lines.indexed)
        if (i < items.length && items[i]['verdict'] is Map<String, dynamic>)
          adviceFromJson(l.item, items[i]['verdict'] as Map<String, dynamic>, xpAwarded: items[i]['log']['xp_awarded'] as int? ?? 0)
        else if (l.removed)
          Advice(
            item: l.item,
            verdict: Verdict.avoid,
            headline: 'Kept it out',
            reason: 'Thanks for taking it back out.',
            xpAwarded: items[i]['log']['xp_awarded'] as int? ?? 0,
          )
        else
          // No readings to judge against yet: the add is still logged.
          Advice(
            item: l.item,
            verdict: Verdict.careful,
            headline: 'Saved',
            reason: 'No current readings to judge this addition. Check the bin before adding more.',
            xpAwarded: items[i]['log']['xp_awarded'] as int? ?? 0,
          ),
    ];
  }

  @override
  Future<void> dismissReviewedDrop(Drop drop) => dismissDrop(drop.id);

  // --- league ------------------------------------------------------------------------

  @override
  Future<List<LeagueMember>> leagueCohort() async {
    if (config.token != null) return const [];
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
    return DropSession(id: j['session_id'] as String, expiresAt: DateTime.parse(j['expires_at'] as String).toLocal());
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
    final j =
        await _post('/drops/$dropId/confirm', {
              'items': [
                for (final i in items)
                  {
                    'label': i.label,
                    'catalog_id': i.catalogId,
                    // The backend overrides this by its own rules; sending 'unknown'
                    // lets it decide rather than asserting a category we guessed.
                    'category': i.category?.name ?? 'unknown',
                    if (i.amount != null) 'amount': i.amount,
                    if (i.pieceCount != null) 'piece_count': i.pieceCount,
                    if (i.quantityG != null) 'quantity_g': i.quantityG!.round(),
                    'removed': i.removed,
                    'was_advised': i.wasAdvised,
                    if (i.adviceId != null) 'advice_id': i.adviceId,
                  },
              ],
            })
            as Map<String, dynamic>;

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
    return DropResult(dropId: (j['drop_id'] as num?)?.toInt() ?? dropId, corrected: j['corrected'] == true, verdicts: verdicts, xpAwarded: xp);
  }

  @override
  Future<void> dismissDrop(int dropId) => _post('/drops/$dropId/dismiss', const <String, dynamic>{});

  @override
  Future<CameraDrop> submitPhoto(Uint8List jpeg) async {
    final j = await _post('/bins/${config.binId}/drops/photo', {'image_jpeg_b64': base64Encode(jpeg)}) as Map<String, dynamic>;
    return dropFromJson(j);
  }

  // --- Trunc -------------------------------------------------------------------------

  @override
  Future<TruncReply> askTrunc(String message, {List<TruncTurn> history = const [], bool includePhotos = true}) async {
    final j =
        await _post('/bins/${config.binId}/chat', {
              'message': message,
              'history': [
                for (final t in history) {'role': t.role.name, 'text': t.text},
              ],
              'include_photos': includePhotos,
            })
            as Map<String, dynamic>;
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
  final ambient = _d(air['ambient_temp_c']) ?? 0;
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
    topMeasured: top['measured'] == true && top['moisture_pct'] != null,
    topTemperatureMeasured: top['temp_c'] != null,
    bottomTemperatureMeasured: bottom['temp_c'] != null,
    airMeasured: air['co2_ok'] != false && air['co2_ppm'] != null,
    ambientMeasured: air['ambient_temp_c'] != null,
    moistureCalibrated: j['moisture_calibrated'] == true,
    bottomMoistureCalibrated: bottom['moisture_calibrated'] == true,
    topMoistureRaw: (top['moisture_raw'] as num?)?.toInt(),
    bottomMoistureRaw: (bottom['moisture_raw'] as num?)?.toInt(),
  );
}

/// POST /bins/{id}/advice/check -> Advice. pair_with names are matched to the
/// catalog; anything it doesn't know is dropped.
Advice adviceFromJson(FoodItem item, Map<String, dynamic> j, {int? xpAwarded}) {
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
    xpAwarded: xpAwarded,
  );
}

/// GET /bins/{id}/drops/pending item -> Drop.
Drop reviewedDropFromJson(Map<String, dynamic> j) {
  final thumb = j['thumbnail_jpeg_b64'] as String? ?? '';
  return Drop(
    id: (j['id'] as num).toInt(),
    source: j['source'] as String? ?? 'camera',
    geminiOk: j['gemini_ok'] != false,
    thumbnail: thumb.isEmpty ? null : base64Decode(thumb),
    items: [
      for (final i in ((j['items'] as List?) ?? const []).cast<Map<String, dynamic>>())
        Detection(
          label: (i['label'] as String?) ?? 'Something',
          catalogId: i['catalog_id'] == null || i['catalog_id'] == 'unknown' ? null : i['catalog_id'] as String,
          category: FoodCategory.values.where((c) => c.name == i['category']).firstOrNull,
          amount: Amount.values.where((a) => a.name == i['amount']).firstOrNull,
          confidence: _d(i['confidence']) ?? 0,
          pieceCount: (i['piece_count'] as num?)?.toInt(),
          estimatedGrams: _d(i['est_grams']),
          box: (i['box_2d'] as List?)?.map((v) => (v as num).toDouble()).toList(),
        ),
    ],
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
    guesses.add(
      DropGuess(
        label: label,
        catalogId: catalogId,
        confidence: _d(g['confidence']) ?? 0,
        item: foodForLabel(label, catalogId),
        category: FoodCategory.values.where((c) => c.name == g['category']).firstOrNull,
        amount: g['amount'] as String?,
        estGrams: _d(g['est_grams']),
        pieceCount: (g['piece_count'] as num?)?.toInt(),
        box: (g['box_2d'] as List?)?.cast<num>().map((n) => n.toInt()).toList(),
      ),
    );
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
    need: BinNeed.values.where((n) => n.name == j['need']).firstOrNull,
    context: TruncContext(
      // Null when the bin has never reported, which is not an error: a general
      // question does not need a reading.
      readingsAt: at == null ? null : DateTime.tryParse(at)?.toLocal(),
      recentAdds: (ctx['recent_adds'] as num?)?.toInt() ?? 0,
      photos: (ctx['photos'] as num?)?.toInt() ?? 0,
      readingsStale: ctx['readings_stale'] == true,
    ),
  );
}
