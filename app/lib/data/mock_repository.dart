import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import '../domain/advice_rules.dart';
import '../domain/trunc_guidance.dart';
import '../domain/drop.dart';
import '../domain/models.dart';
import '../domain/inventory.dart';
import '../domain/drop_history.dart';
import '../domain/calibration.dart';
import '../domain/xp_rules.dart';
import 'calmpost_repository.dart';
import 'food_catalog.dart';

/// Demo scenarios. Switch from the hidden debug panel (long-press the health score).
enum Scenario { healthy, tooWet, tooDry, curing, ready }

/// What the mock camera "sees" after you arm it (?drop= on the web preview).
enum MockDrop { banana, check, mixed, unclear, nothing }

extension ScenarioLabel on Scenario {
  String get label => switch (this) {
    Scenario.healthy => 'Healthy',
    Scenario.tooWet => 'Too wet',
    Scenario.tooDry => 'Too dry',
    Scenario.curing => 'Curing',
    Scenario.ready => 'Ready to harvest',
  };
}

class _Base {
  const _Base(this.topM, this.topT, this.botM, this.botT, this.co2, this.slope, this.greens, this.browns, this.top, this.bottom, this.healthyHours);
  final double topM, topT, botM, botT, co2, slope, greens, browns, healthyHours;
  final Stage top, bottom;
}

const _ambient = 21.0;

const _bases = {
  Scenario.healthy: _Base(57, 33, 48, 24.5, 2400, -1.5, 3, 7.5, Stage.active, Stage.curing, 4.5),
  Scenario.tooWet: _Base(76, 31, 63, 25, 3900, 1, 8, 4, Stage.active, Stage.curing, 0.5),
  Scenario.tooDry: _Base(24, 23.5, 31, 22, 750, -2, 2, 9, Stage.active, Stage.curing, 1),
  Scenario.curing: _Base(50, 34, 45, 22.5, 1150, -8, 3, 8, Stage.active, Stage.curing, 5.5),
  Scenario.ready: _Base(50, 36, 43, 21.4, 680, -12, 3, 8, Stage.active, Stage.ready, 6),
};

class MockRepository implements CalmpostRepository {
  final _calibrations = <int, CalibrationResult>{};
  @override
  Future<CalibrationResult> calibrateProbe({required int probe, required int dry, required int wet, bool backfill = false}) async {
    final error = calibrationError(probe, dry, wet);
    if (error != null) throw ArgumentError(error);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return _calibrations[probe] = CalibrationResult(probe: probe, dry: dry, wet: wet);
  }

  final _history = <int, PastDrop>{};
  final _photos = <int, Uint8List>{};
  @override
  Future<DropHistoryPage> dropHistory({String? before, int limit = 20}) async {
    final cursor = before == null ? null : DateTime.parse(before);
    final rows = _history.values.where((d) => cursor == null || d.time.isBefore(cursor)).toList()..sort((a, b) => b.time.compareTo(a.time));
    final page = rows.take(limit).toList();
    return DropHistoryPage(drops: page, nextBefore: rows.length > limit ? page.last.time.toUtc().toIso8601String() : null);
  }

  @override
  Future<Uint8List?> dropPhoto(int id) async => _photos[id];

  void _archive(Drop drop, List<PastDropItem> items, {bool dismissed = false, bool changed = false}) {
    if (_history.containsKey(drop.id)) return;
    if (drop.thumbnail != null) _photos[drop.id] = drop.thumbnail!;
    _history[drop.id] = PastDrop(
      id: drop.id,
      time: DateTime.now(),
      status: dismissed ? DropStatus.dismissed : DropStatus.confirmed,
      source: drop.source,
      guesses: drop.items.map((d) => d.label).toList(),
      items: items,
      corrected: changed || dismissed,
      hasPhoto: drop.thumbnail != null,
    );
  }

  @override
  bool get serverGame => false;
  @override
  Future<Map<String, dynamic>> loadGame() async => {};
  @override
  Future<Map<String, dynamic>> gameAction(String action, Map<String, dynamic> args) async => {};
  @override
  Future<void> cancelDropSession(DropSession session) async {
    _cancelledSessions.add(session.id);
    _pending.removeWhere((drop) => drop.sessionId == session.id);
  }

  @override
  Future<Drop?> pendingDrop() async => _pending.isEmpty ? null : Drop.fromCamera(_pending.first);
  MockRepository(this.scenario);

  final _inventoryLogs = <({FoodItem item, double grams, int? pieces, DateTime time, String source})>[];
  final _loggedRequests = <String>{};
  final _reviewed = <int, List<Advice>>{};
  final _confirmed = <int, DropResult>{};

  @override
  Future<CompostInventory> inventory({String period = 'all'}) async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: now.weekday % 7));
    final grouped = <String, InventoryItem>{};
    for (final log in _inventoryLogs) {
      if (period == 'week' && log.time.toUtc().isBefore(start)) continue;
      final key = '${log.item.id}:${log.item.category.name}';
      final old = grouped[key];
      grouped[key] = InventoryItem(
        key: key,
        label: log.item.name,
        category: log.item.category.name,
        grams: (old?.grams ?? 0) + log.grams,
        pieces: (old?.pieces ?? 0) + (log.pieces ?? 0),
        entries: (old?.entries ?? 0) + 1,
        uncountedEntries: (old?.uncountedEntries ?? 0) + (log.pieces == null ? 1 : 0),
        visionEntries: (old?.visionEntries ?? 0) + (log.source == 'manual' ? 0 : 1),
        lastAddedAt: log.time,
      );
    }
    return CompostInventory(items: grouped.values.toList()..sort((a, b) => b.grams.compareTo(a.grams)));
  }

  final Scenario scenario;
  final _rand = math.Random(7);

  // Simulated physical effect of what's been added: browns soak up water,
  // greens add it. Real sensors do this for free.
  double _moistureTarget = 0, _moisture = 0, _greens = 0, _browns = 0;

  _Base get _b => _bases[scenario]!;

  BinSnapshot _snapshot(double t) {
    double wobble(double amp, double speed, double seed) => math.sin(t * speed + seed) * amp + (_rand.nextDouble() - 0.5) * amp * 0.3;
    final b = _b;
    _moisture += (_moistureTarget - _moisture) * 0.35;
    return BinSnapshot(
      time: DateTime.now(),
      topMoisture: (b.topM + _moisture + wobble(0.8, 0.7, 1)).clamp(5, 95),
      topTemp: b.topT + wobble(0.3, 0.4, 2),
      bottomMoisture: b.botM + wobble(0.5, 0.5, 3),
      bottomTemp: b.botT + wobble(0.2, 0.3, 4),
      bottomTemperatureMeasured: false,
      co2: b.co2 + wobble(b.co2 * 0.02, 0.6, 5),
      ambientTemp: _ambient,
      co2SlopePerDay: b.slope,
      greens7d: b.greens + _greens,
      browns7d: b.browns + _browns,
      topStage: b.top,
      bottomStage: b.bottom,
      healthyHoursToday: b.healthyHours,
      bottomMoistureCalibrated: _calibrations.containsKey(2),
    );
  }

  BinSnapshot? _last;

  @override
  Stream<BinSnapshot> watchBin() async* {
    var t = 0.0;
    yield _last = _snapshot(t);
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 3));
      t += 1;
      yield _last = _snapshot(t);
    }
  }

  @override
  Future<List<TrendPoint>> trends(Zone zone, Metric metric) async {
    final b = _b;
    final now = DateTime.now();
    final target = switch (metric) {
      Metric.moisture => zone == Zone.bottom ? b.botM : b.topM,
      Metric.temperature => zone == Zone.bottom ? b.botT : b.topT,
      Metric.co2 => b.co2,
    };
    // 24 h at 15-minute buckets, drifting from a calmer start toward today's value.
    final start = switch (metric) {
      Metric.moisture => 50.0,
      Metric.temperature => zone == Zone.bottom ? 23.0 : 35.0,
      Metric.co2 => b.co2 * (b.slope < 0 ? 1.18 : 0.9),
    };
    final amp = switch (metric) {
      Metric.moisture => 2.2,
      Metric.temperature => 1.4,
      Metric.co2 => b.co2 * 0.06,
    };
    final r = math.Random(zone.index * 10 + metric.index);
    return List.generate(96, (i) {
      final f = i / 95;
      final eased = f * f * (3 - 2 * f);
      final v = start + (target - start) * eased + math.sin(i / 7 + zone.index) * amp + (r.nextDouble() - 0.5) * amp * 0.6;
      return TrendPoint(now.subtract(Duration(minutes: 15 * (95 - i))), v);
    });
  }

  @override
  Future<Advice> checkItem(FoodItem item) async {
    await Future<void>.delayed(const Duration(milliseconds: 650)); // feels like a real call
    return adviseFor(item, _last ?? _snapshot(0), foodById);
  }

  @override
  Future<int?> logItem(FoodItem item, {bool added = true, double? quantityG, int? pieceCount, String? requestId, bool wasAdvised = false}) async {
    _recordItem(item, added: added, quantityG: quantityG, pieceCount: pieceCount, requestId: requestId);
    return null;
  }

  void _recordItem(FoodItem item, {bool added = true, double? quantityG, int? pieceCount, String? requestId, String source = 'manual'}) {
    if (!added) return;
    if (requestId != null && !_loggedRequests.add(requestId)) return;
    if (item.category != FoodCategory.avoid && (quantityG ?? item.grams) > 0) {
      _inventoryLogs.add((item: item, grams: quantityG ?? item.grams, pieces: pieceCount, time: DateTime.now(), source: source));
    }
    final cups = (quantityG ?? item.grams) / 110;
    switch (item.category) {
      case FoodCategory.brown:
        _moistureTarget -= 9;
        _browns += cups;
      case FoodCategory.green:
        _moistureTarget += item.wet ? 6 : 2;
        _greens += cups;
      case FoodCategory.avoid:
        break;
    }
  }

  @override
  Suggestion suggestions(BinSnapshot snapshot) => suggestFor(snapshot, foodById);

  @override
  List<FoodItem> searchFoods(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return foodCatalog;
    return foodCatalog.where((f) => f.name.toLowerCase().contains(q) || f.id.contains(q)).toList();
  }

  @override
  Future<FoodItem> identifyPhoto() async {
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    return foodById['banana_peel']!;
  }

  @override
  FoodItem? food(String id) => foodById[id];

  @override
  Future<List<LeagueMember>> leagueCohort() async => _cohort;

  // --- camera drop-in: a fake detection [dropDelay] after arming -------------

  MockDrop nextDrop = MockDrop.banana;
  Duration dropDelay = const Duration(milliseconds: 2500);

  @override
  Stream<DropEvent> watchDrop(DropSession session) async* {
    _reviewSessions.add(session.id);
    final id = _sessionIds[session.id] ?? _dropId;
    await Future<void>.delayed(dropDelay);
    if (_cancelledSessions.contains(session.id)) return;
    const box = [360.0, 300.0, 660.0, 640.0];
    Detection d(String label, String? id, FoodCategory c, Amount a, double conf) =>
        Detection(label: label, catalogId: id, category: c, amount: a, confidence: conf, box: box);
    final event = switch (nextDrop) {
      MockDrop.banana => DropSeen(Drop(id: id, items: [d('banana peel', 'banana_peel', FoodCategory.green, Amount.handful, 0.86)])),
      MockDrop.check => DropSeen(
        Drop(
          id: id,
          items: [
            d('banana peel', 'banana_peel', FoodCategory.green, Amount.handful, 0.91),
            d('something papery', 'newspaper', FoodCategory.brown, Amount.small, 0.44),
          ],
        ),
      ),
      MockDrop.mixed => DropSeen(Drop(id: id, items: [d('mixed scraps: rice, peels', 'mixed_scraps', FoodCategory.green, Amount.large, 0.41)])),
      MockDrop.unclear => DropSeen(Drop(id: id, items: const [], geminiOk: false)),
      MockDrop.nothing => const DropNothing(),
    };
    _pending.removeWhere((d) => d.sessionId == session.id);
    if (event case DropSeen(:final drop)) {
      _pending.add(
        CameraDrop(
          id: drop.id,
          binId: 'bin-001',
          sessionId: session.id,
          time: DateTime.now(),
          status: DropStatus.pending,
          geminiOk: drop.geminiOk,
          latencyMs: dropDelay.inMilliseconds,
          source: drop.source,
          thumbnailJpeg: drop.thumbnail,
          guesses: [
            for (final d in drop.items)
              DropGuess(
                label: d.label,
                catalogId: d.catalogId ?? 'unknown',
                confidence: d.confidence,
                item: foodById[d.catalogId],
                category: d.category,
                amount: d.amount?.name,
                estGrams: d.estimatedGrams,
                pieceCount: d.pieceCount,
                box: d.box?.map((v) => v.round()).toList(),
              ),
          ],
        ),
      );
    }
    yield event;
  }

  @override
  Future<List<Advice>> confirmReviewedDrop(Drop drop, List<DropLine> lines, {Set<String> advisedIds = const {}}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_reviewed.containsKey(drop.id)) return _reviewed[drop.id]!;
    final snap = _last ?? _snapshot(0);
    final out = <Advice>[];
    for (final l in lines) {
      if (l.removed) {
        out.add(Advice(item: l.item, verdict: Verdict.avoid, headline: 'Kept it out', reason: 'Thanks for taking it back out.'));
        continue;
      }
      out.add(adviseFor(l.item, snap, foodById));
      _recordItem(l.item, quantityG: l.grams, pieceCount: l.pieceCount, requestId: 'drop:${drop.id}:${out.length}', source: drop.source);
    }
    _pending.removeWhere((d) => d.id == drop.id);
    _archive(drop, [
      for (final l in lines) PastDropItem(label: l.item.name, category: l.item.category.name, grams: l.grams, pieces: l.pieceCount, removed: l.removed),
    ], changed: corrected(drop, lines));
    _reviewed[drop.id] = out;
    return out;
  }

  @override
  Future<void> dismissReviewedDrop(Drop drop) async {
    await dismissDrop(drop.id);
    _archive(drop, [], dismissed: true);
  }
  // --- camera drop-in ---------------------------------------------------------
  //
  // No camera and no backend here: arming queues a detection a beat later, so
  // the sheet can be built and demoed on a laptop with nothing plugged in.
  // Walk through the scripted guesses with [Scenario] unchanged; each arm
  // serves the next one and then wraps around.

  int _dropId = 0, _nextGuess = 0;
  final List<CameraDrop> _pending = [];
  final Set<String> _cancelledSessions = {};
  final Set<String> _reviewSessions = {};
  final Map<String, int> _sessionIds = {};
  double _confirmedGrams = 0;
  int _confirmedActionXp = 0;
  DateTime _confirmationDay = dayOf(DateTime.now());

  /// What the camera "sees", in order: a clean green, a pair, an unknown item
  /// the user has to name, and a keep-out item. Covers the cases a sheet has
  /// to handle without needing hardware to produce them.
  static const _scripted = <List<(String, String, double)>>[
    [('banana peel', 'banana_peel', 0.95)],
    [('coffee grounds', 'coffee_grounds', 0.88), ('eggshells', 'eggshells', 0.71)],
    [('something leafy', 'unknown', 0.41)],
    [('cheese rind', 'cheese', 0.83)],
  ];

  @override
  Future<DropSession> startDropSession() async {
    final session = DropSession(id: 'mock-${++_dropId}', expiresAt: DateTime.now().add(const Duration(seconds: 60)));
    _sessionIds[session.id] = _dropId;
    final guesses = _scripted[_nextGuess++ % _scripted.length];
    final dropId = _dropId;
    // Roughly what a real drop costs end to end, so a spinner gets exercised.
    Future<void>.delayed(const Duration(milliseconds: 2000), () {
      if (_cancelledSessions.contains(session.id) || _reviewSessions.contains(session.id)) return;
      _pending.add(
        CameraDrop(
          id: dropId,
          binId: 'bin-001',
          sessionId: session.id,
          time: DateTime.now(),
          status: DropStatus.pending,
          geminiOk: true,
          latencyMs: 1400,
          model: 'mock',
          guesses: [
            for (final (label, id, confidence) in guesses)
              DropGuess(label: label, catalogId: id, confidence: confidence, item: foodById[id], category: foodById[id]?.category, amount: 'handful'),
          ],
        ),
      );
    });
    return session;
  }

  @override
  Stream<List<CameraDrop>> watchDrops() async* {
    while (true) {
      yield List.unmodifiable(_pending);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Future<DropResult> confirmDrop(int dropId, List<DropConfirmation> items) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_confirmed.containsKey(dropId)) return _confirmed[dropId]!;
    final drop = _pending.where((d) => d.id == dropId).firstOrNull;
    _pending.removeWhere((d) => d.id == dropId);

    final verdicts = <Advice>[];
    var xp = 0;
    final today = dayOf(DateTime.now());
    if (today != _confirmationDay) {
      _confirmationDay = today;
      _confirmedGrams = 0;
      _confirmedActionXp = 0;
    }
    final snap = _last ?? _snapshot(0);
    for (final i in items) {
      final amount = Amount.values.where((a) => a.name == i.amount).firstOrNull ?? Amount.handful;
      final item = foodById[i.catalogId] ?? customFood(i.label, i.category ?? FoodCategory.green, amount);
      final advice = adviseFor(item, snap, foodById);
      var reward = 0;
      if (!i.removed) {
        final grams = i.quantityG ?? amountGrams[amount]!;
        if (item.category != FoodCategory.avoid) {
          reward = volumeXp(grams, alreadyLogged: _confirmedGrams);
          _confirmedGrams += grams;
          if (i.wasAdvised && suggestions(snap).add.any((f) => f.id == item.id)) {
            reward += Xp.followedSuggestion;
          }
        }
        _recordItem(item, quantityG: grams, pieceCount: i.pieceCount, source: drop?.source ?? 'camera');
        verdicts.add(advice);
      } else if (item.category == FoodCategory.avoid) {
        reward = Xp.avoidedBadAdd;
      }
      final paid = xpForAction(base: reward, earnedToday: _confirmedActionXp);
      _confirmedActionXp += paid;
      xp += paid;
    }

    final guessed = drop?.guesses.map((g) => (g.catalogId, g.label.toLowerCase())).toSet() ?? const {};
    final confirmed = items.map((i) => (i.catalogId, i.label.toLowerCase())).toSet();
    if (drop != null) {
      _archive(Drop.fromCamera(drop), [
        for (final i in items)
          PastDropItem(label: i.label, category: i.category?.name ?? 'unknown', grams: i.quantityG, pieces: i.pieceCount, removed: i.removed),
      ], changed: guessed.isNotEmpty && !_setEquals(guessed, confirmed));
    }
    return _confirmed[dropId] = DropResult(dropId: dropId, corrected: guessed.isNotEmpty && !_setEquals(guessed, confirmed), verdicts: verdicts, xpAwarded: xp);
  }

  @override
  Future<void> dismissDrop(int dropId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final drop = _pending.where((d) => d.id == dropId).firstOrNull;
    if (drop != null) _archive(Drop.fromCamera(drop), [], dismissed: true);
    _pending.removeWhere((d) => d.id == dropId);
  }

  @override
  Future<CameraDrop> submitPhoto(Uint8List jpeg) async {
    // About what a real identification costs, so a spinner gets exercised.
    await Future<void>.delayed(const Duration(milliseconds: 1800));

    // An empty image stands in for "the model could not name it", which is the
    // case the sheet has to let the user answer by hand. Easier to trigger
    // from a test or a debug button than a genuinely unrecognisable photo.
    final failed = jpeg.isEmpty;
    final drop = CameraDrop(
      id: ++_dropId,
      binId: 'bin-001',
      sessionId: 'photo-mock-$_dropId',
      time: DateTime.now(),
      status: DropStatus.pending,
      source: 'photo',
      geminiOk: !failed,
      latencyMs: 1800,
      model: failed ? 'rules-fallback' : 'mock',
      error: failed ? 'could not identify anything in the photo' : null,
      thumbnailJpeg: jpeg.isEmpty ? null : jpeg,
      guesses: failed
          ? const []
          : [
              DropGuess(
                label: 'banana peel',
                catalogId: 'banana_peel',
                confidence: 0.93,
                item: foodById['banana_peel'],
                category: FoodCategory.green,
                amount: 'handful',
                estGrams: 110,
                // Roughly centred, so a bounding-box overlay has something
                // plausible to draw on a portrait photo.
                box: [180, 260, 760, 720],
              ),
            ],
    );
    _pending.add(drop);
    return drop;
  }

  // --- Trunc ------------------------------------------------------------------
  //
  // Scripted so the chat UI can be built with no backend, no API key and no
  // Gemini quota. Keyword-matched rather than random, so a given question
  // always gives the same answer and a screenshot is reproducible.
  //
  // The four replies below are the four states a chat screen has to handle:
  // a normal answer, one that leaned on the readings, an off-topic refusal,
  // and a rules-fallback when the model is unreachable. Ask "test fallback"
  // or something off topic to see those two without touching the backend.

  @override
  Future<TruncReply> askTrunc(String message, {List<TruncTurn> history = const [], bool includePhotos = true}) async {
    // Long enough that a typing indicator is worth building, and close to what
    // a real call costs with photos attached.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    final q = message.toLowerCase();
    final snap = _last ?? _snapshot(0);
    final a = guidanceFor(snap);
    final context = TruncContext(
      readingsAt: snap.time,
      readingsStale: snap.readingsStale,
      recentAdds: _inventoryLogs.where((l) => DateTime.now().difference(l.time) < const Duration(hours: 48)).length,
      photos: 0, // The mock has no real frames to send to a model.
    );
    final item = truncRequestedItem(message) ?? truncFollowupItem(message, history);
    if (!_soundsLikeCompost(q) && item == null && !q.contains('fallback') && !q.contains('test error')) {
      return TruncReply(
        reply: "I only know about composting, so I'll stay out of that one. Ask about your bin or what to add.",
        model: 'mock',
        onTopic: false,
        usedReadings: false,
        context: context,
      );
    }
    var text = item != null
        ? truncMaterialAnswer(snap, item, foodCatalog)
        : q.contains('what are browns')
        ? 'Browns are dry materials such as plain shredded cardboard and dry leaves. ${a.summary}'
        : a.summary;
    if (['how much', 'how many', 'exact'].any(q.contains)) {
      text = 'I cannot calculate an exact dose or number of scraps from two moisture points and estimated additions. $text';
    }
    return TruncReply(
      reply: text,
      model: q.contains('fallback') || q.contains('test error') ? 'rules-fallback' : 'mock',
      onTopic: true,
      usedReadings: a.usable && !text.contains("isn't in my list") && !text.contains('Keep $item out'),
      context: context,
      need: a.need,
    );
  }

  static bool _soundsLikeCompost(String q) => const [
    'compost',
    'bin',
    'smell',
    'moist',
    'wet',
    'dry',
    'brown',
    'green',
    'worm',
    'heat',
    'hot',
    'layer',
    'harvest',
    'peel',
    'scrap',
    'cardboard',
    'coffee',
    'egg',
    'fruit',
    'veg',
    'pest',
    'fly',
    'mould',
    'mold',
    'rot',
    'add',
    'put',
  ].any(q.contains);
}

bool _setEquals(Set<(String, String)> a, Set<(String, String)> b) => a.length == b.length && a.every(b.contains);

const _names = [
  ('Priya S.', 342, true, 41),
  ('mossy_mia', 318, false, 12),
  ('Theo', 296, false, 88),
  ('lena.grows', 281, false, 23),
  ('Marcus O.', 264, true, 9),
  ('compost_kai', 251, false, 60),
  ('Noor', 238, false, 17),
  ('Hiro T.', 226, false, 5),
  ('Ava K.', 212, true, 33),
  ('Omar', 199, false, 14),
  ('Sofia R.', 176, false, 2),
  ('jules', 168, false, 7),
  ('Mei', 157, false, 21),
  ('Liam O.', 149, false, 4),
  ('Zara', 131, false, 11),
  ('Diego', 122, false, 3),
  ('Hannah B.', 110, false, 6),
  ('Kofi', 98, true, 19),
  ('Ines', 87, false, 1),
  ('Ravi', 76, false, 8),
  ('Grace', 64, false, 2),
  ('Tomás', 55, false, 3),
  ('Yuki', 47, false, 1),
  ('Elif', 38, false, 0),
  ('Sam P.', 30, false, 2),
  ('Ola', 21, false, 0),
  ('Nina', 14, false, 1),
  ('Arjun', 8, false, 0),
  ('Chloe', 0, false, 0),
];

final _cohort = [for (final (i, n) in _names.indexed) LeagueMember(name: n.$1, xp: n.$2, isFriend: n.$3, streak: n.$4, colorIndex: i % 6)];
