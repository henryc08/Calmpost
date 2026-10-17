import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/advice_rules.dart';
import '../domain/drop.dart';
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
  ApiRepository(this.config, {http.Client? client, this.pollEvery = const Duration(seconds: 3), this.dropPollEvery = const Duration(seconds: 1)})
    : _http = client ?? http.Client();

  final ApiConfig config;
  final Duration pollEvery;

  /// How often the drop sheet asks whether the camera saw something.
  final Duration dropPollEvery;
  final http.Client _http;
  BinSnapshot? _last;
  List<int> _crateIds = [];

  @override
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
      _get('/bins/${config.binId}/logs'),
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
      'check-in' => '$user/check-in',
      'quest' => '/quests/${args['id']}/claim',
      'daily' => '$user/daily-goal/${args['index']}/claim',
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
    return pending.isEmpty ? null : dropFromJson(pending.first as Map<String, dynamic>);
  }

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
  Future<int?> logItem(FoodItem item, {bool added = true, double? quantityG, String? requestId, bool wasAdvised = false}) async {
    final j =
        await _post('/bins/${config.binId}/logs', {
              'item': item.name,
              'catalog_id': item.id,
              'category': item.category.name,
              'action': added ? 'added' : 'skipped',
              'quantity_g': (quantityG ?? item.grams).round(),
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
  Future<DropSession> startDropSession() async {
    final j = await _post('/bins/${config.binId}/drops/session', const {}) as Map<String, dynamic>;
    return DropSession(j['session_id'] as String, DateTime.parse(j['expires_at'] as String).toLocal());
  }

  @override
  Stream<DropEvent> watchDrop(DropSession session) async* {
    var reportedButMissing = false;
    while (true) {
      final pending = (await _get('/bins/${config.binId}/drops/pending') as List).cast<Map<String, dynamic>>();
      final mine = pending.where((d) => d['session_id'] == session.id).firstOrNull;
      if (mine != null) {
        yield DropSeen(dropFromJson(mine));
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
  Future<List<Advice>> confirmDrop(Drop drop, List<DropLine> lines, {Set<String> advisedIds = const {}}) async {
    final j =
        await _post('/drops/${drop.id}/confirm', {
              'items': [
                for (final l in lines)
                  {
                    'label': l.item.name,
                    'catalog_id': l.isCustom ? 'unknown' : l.item.id,
                    'category': l.item.category.name,
                    'amount': l.amount.name,
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
  Future<void> dismissDrop(Drop drop) async => _post('/drops/${drop.id}/dismiss', const {});

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
Drop dropFromJson(Map<String, dynamic> j) {
  final thumb = j['thumbnail_jpeg_b64'] as String? ?? '';
  return Drop(
    id: (j['id'] as num).toInt(),
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
          box: (i['box_2d'] as List?)?.map((v) => (v as num).toDouble()).toList(),
        ),
    ],
  );
}
