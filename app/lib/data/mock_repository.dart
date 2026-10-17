import 'dart:async';
import 'dart:math' as math;

import '../domain/advice_rules.dart';
import '../domain/models.dart';
import 'calmpost_repository.dart';
import 'food_catalog.dart';

/// Demo scenarios. Switch from the hidden debug panel (long-press the health score).
enum Scenario { healthy, tooWet, tooDry, curing, ready }

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
  Scenario.healthy: _Base(57, 33, 34, 24.5, 2400, -1.5, 3, 4.4, Stage.active, Stage.curing, 4.5),
  Scenario.tooWet: _Base(76, 31, 63, 25, 3900, 1, 8, 4, Stage.active, Stage.curing, 0.5),
  Scenario.tooDry: _Base(24, 23.5, 31, 22, 750, -2, 2, 9, Stage.active, Stage.curing, 1),
  Scenario.curing: _Base(50, 34, 45, 22.5, 1150, -8, 3, 8, Stage.active, Stage.curing, 5.5),
  Scenario.ready: _Base(50, 36, 43, 21.4, 680, -12, 3, 8, Stage.active, Stage.ready, 6),
};

class MockRepository implements CalmpostRepository {
  MockRepository(this.scenario);

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
      co2: b.co2 + wobble(b.co2 * 0.02, 0.6, 5),
      ambientTemp: _ambient,
      co2SlopePerDay: b.slope,
      greens7d: b.greens + _greens,
      browns7d: b.browns + _browns,
      topStage: b.top,
      bottomStage: b.bottom,
      healthyHoursToday: b.healthyHours,
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
  Future<void> logItem(FoodItem item) async {
    switch (item.category) {
      case FoodCategory.brown:
        _moistureTarget -= 9;
        _browns += 1;
      case FoodCategory.green:
        _moistureTarget += item.wet ? 6 : 2;
        _greens += 1;
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

  // --- camera drop-in ---------------------------------------------------------
  //
  // No camera and no backend here: arming queues a detection a beat later, so
  // the sheet can be built and demoed on a laptop with nothing plugged in.
  // Walk through the scripted guesses with [Scenario] unchanged; each arm
  // serves the next one and then wraps around.

  int _dropId = 0, _nextGuess = 0;
  final List<CameraDrop> _pending = [];

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
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final session = DropSession(
      id: 'mock-${++_dropId}',
      expiresAt: DateTime.now().add(const Duration(seconds: 60)),
    );
    final guesses = _scripted[_nextGuess++ % _scripted.length];
    // Roughly what a real drop costs end to end, so a spinner gets exercised.
    Future<void>.delayed(const Duration(milliseconds: 2000), () {
      _pending.add(CameraDrop(
        id: _dropId,
        binId: 'bin-001',
        sessionId: session.id,
        time: DateTime.now(),
        status: DropStatus.pending,
        geminiOk: true,
        latencyMs: 1400,
        model: 'mock',
        guesses: [
          for (final (label, id, confidence) in guesses)
            DropGuess(
              label: label,
              catalogId: id,
              confidence: confidence,
              item: foodById[id],
              category: foodById[id]?.category,
              amount: 'handful',
            ),
        ],
      ));
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
    final drop = _pending.where((d) => d.id == dropId).firstOrNull;
    _pending.removeWhere((d) => d.id == dropId);

    final verdicts = <Advice>[];
    var xp = 0;
    for (final i in items) {
      final item = foodById[i.catalogId];
      if (item == null) continue;
      if (!i.removed) {
        await logItem(item);
        verdicts.add(adviseFor(item, _last ?? _snapshot(0), foodById));
      }
      // Mirrors the backend's rules: nothing for an ordinary add, +5 for
      // taking a keep-out item back out, +15 when it was the advised action.
      xp += i.removed ? 5 : (i.wasAdvised ? 15 : 0);
    }

    final guessed = drop?.guesses.map((g) => (g.catalogId, g.label.toLowerCase())).toSet() ?? const {};
    final confirmed = items.map((i) => (i.catalogId, i.label.toLowerCase())).toSet();
    return DropResult(
      dropId: dropId,
      corrected: guessed.isNotEmpty && !_setEquals(guessed, confirmed),
      verdicts: verdicts,
      xpAwarded: xp,
    );
  }

  @override
  Future<void> dismissDrop(int dropId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _pending.removeWhere((d) => d.id == dropId);
  }
}

bool _setEquals(Set<(String, String)> a, Set<(String, String)> b) =>
    a.length == b.length && a.every(b.contains);

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
