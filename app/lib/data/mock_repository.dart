import 'dart:async';
import 'dart:math' as math;

import '../domain/advice_rules.dart';
import '../domain/drop.dart';
import '../domain/models.dart';
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

  // --- camera drop-in: a fake detection [dropDelay] after arming -------------

  MockDrop nextDrop = MockDrop.banana;
  Duration dropDelay = const Duration(milliseconds: 2500);
  var _dropIds = 0;

  @override
  Future<DropSession> startDropSession() async => DropSession('mock-${++_dropIds}', DateTime.now().add(const Duration(seconds: 60)));

  @override
  Stream<DropEvent> watchDrop(DropSession session) async* {
    await Future<void>.delayed(dropDelay);
    const box = [360.0, 300.0, 660.0, 640.0];
    Detection d(String label, String? id, FoodCategory c, Amount a, double conf) =>
        Detection(label: label, catalogId: id, category: c, amount: a, confidence: conf, box: box);
    yield switch (nextDrop) {
      MockDrop.banana => DropSeen(Drop(id: _dropIds, items: [d('banana peel', 'banana_peel', FoodCategory.green, Amount.handful, 0.86)])),
      MockDrop.check => DropSeen(
        Drop(
          id: _dropIds,
          items: [
            d('banana peel', 'banana_peel', FoodCategory.green, Amount.handful, 0.91),
            d('something papery', 'newspaper', FoodCategory.brown, Amount.small, 0.44),
          ],
        ),
      ),
      MockDrop.mixed => DropSeen(Drop(id: _dropIds, items: [d('mixed scraps: rice, peels', 'mixed_scraps', FoodCategory.green, Amount.large, 0.41)])),
      MockDrop.unclear => DropSeen(Drop(id: _dropIds, items: const [], geminiOk: false)),
      MockDrop.nothing => const DropNothing(),
    };
  }

  @override
  Future<List<Advice>> confirmDrop(Drop drop, List<DropLine> lines, {Set<String> advisedIds = const {}}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final snap = _last ?? _snapshot(0);
    final out = <Advice>[];
    for (final l in lines) {
      if (l.removed) {
        out.add(Advice(item: l.item, verdict: Verdict.avoid, headline: 'Kept it out', reason: 'Thanks for taking it back out.'));
        continue;
      }
      out.add(adviseFor(l.item, snap, foodById));
      await logItem(l.item);
    }
    return out;
  }

  @override
  Future<void> dismissDrop(Drop drop) async {}
}

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
