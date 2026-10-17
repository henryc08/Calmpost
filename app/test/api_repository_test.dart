import 'dart:async';
import 'dart:convert';

import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/domain/health_score.dart';
import 'package:calmpost/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shaped like the real GET /bins/bin-001/live with today's hardware: one
/// probe (top), so the bottom layer is unmeasured.
Map<String, dynamic> live({double topMoisture = 75.8, bool bottomMeasured = false}) => {
  'bin_id': 'bin-001',
  'time': '2026-10-17T13:42:00Z',
  'last_seen_at': '2026-10-17T13:42:00Z',
  'stale': false,
  'layers': [
    {'layer': 'top', 'label': 'Top', 'measured': true, 'moisture_pct': topMoisture, 'moisture_state': 'wet', 'temp_c': 31.0, 'stage': 'active'},
    {
      'layer': 'bottom',
      'label': 'Bottom',
      'measured': bottomMeasured,
      'moisture_pct': bottomMeasured ? 48.0 : null,
      'moisture_state': bottomMeasured ? 'ok' : 'unknown',
      'temp_c': bottomMeasured ? 23.0 : null,
      'stage': 'started',
    },
  ],
  'air': {'co2_ppm': 3600.0, 'co2_ok': true, 'co2_slope_per_day': 4.5, 'ambient_temp_c': 22.0, 'air_humidity_pct': 70.0},
  'health_components': {'moisture': 36.8, 'temperature': 100.0, 'co2': 100.0, 'balance': 7.8},
  'balance': 'needs_browns',
  'greens_7d': 14.85,
  'browns_7d': 4.6,
  'healthy_band': [40, 60],
  'moisture_calibrated': true,
  'healthy_hours_today': 1.5,
  'notes': ['Only one probe is fitted, so the bottom layer is unmeasured.'],
};

ApiRepository repo(Future<http.Response> Function(http.Request r) handler) =>
    ApiRepository(const ApiConfig(baseUrl: 'http://bin.test', apiKey: 'k'), client: MockClient(handler), pollEvery: const Duration(milliseconds: 10));

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('live JSON maps to a snapshot, and an unprobed bottom layer stays unmeasured', () {
    final s = snapshotFromJson(live());
    expect(s.topMoisture, 75.8);
    expect(s.topStage, Stage.active);
    expect(s.co2, 3600);
    expect(s.ambientTemp, 22);
    expect(s.co2SlopePerDay, 4.5);
    expect(s.healthyHoursToday, 1.5);
    expect(s.bottomMeasured, isFalse);
    expect(zoneState(s, Zone.bottom), ZoneState.unknown);

    // The health score leaves the unmeasured layer out instead of scoring a placeholder.
    final withBottom = snapshotFromJson(live(bottomMeasured: true));
    expect(withBottom.bottomMoisture, 48);
    expect(computeHealth(s).moisture, bandScore(75.8, moistureLo, moistureHi, 25));
  });

  test('watchBin polls /live with the API key and keeps going after an error', () async {
    var calls = 0;
    final r = repo((req) async {
      expect(req.url.path, '/bins/bin-001/live');
      expect(req.headers['X-API-Key'], 'k');
      calls++;
      return calls == 2 ? http.Response('down', 503) : json(live(topMoisture: 40.0 + calls));
    });
    final events = <Object>[];
    final three = Completer<void>();
    void add(Object e) {
      events.add(e);
      if (events.length == 3 && !three.isCompleted) three.complete();
    }

    final sub = r.watchBin().listen(add, onError: add);
    await three.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
    expect(events[0], isA<BinSnapshot>());
    expect(events[1], isA<ApiException>());
    expect(events[2], isA<BinSnapshot>()); // still polling after the 503
  });

  test('scrap check maps the verdict and matches pair_with to the catalog', () async {
    final r = repo((req) async {
      expect(req.url.path, '/bins/bin-001/advice/check');
      expect(jsonDecode(req.body), {'item': 'Banana peel'});
      return json({
        'verdict': 'careful',
        'headline': 'Add browns first',
        'reason': 'Your top layer is 76% wet.',
        'pair_with': ['shredded paper', 'cardboard', 'dry leaves', 'moon rocks'],
      });
    });
    final a = await r.checkItem(foodById['banana_peel']!);
    expect(a.verdict, Verdict.careful);
    expect(a.headline, 'Add browns first');
    expect(a.pairWith, isNotEmpty);
    expect(a.pairWith.every((f) => f.category == FoodCategory.brown), isTrue);
  });

  test('trends: top-layer series, nulls skipped; no bottom series without a probe', () async {
    final r = repo((req) async {
      if (req.url.path.endsWith('/live')) return json(live());
      expect(req.url.queryParameters['metrics'], 'moisture');
      return json({
        'series': [
          {
            'metric': 'moisture',
            'points': [
              {'bucket': '2026-10-17T12:00:00Z', 'value': 70.1},
              {'bucket': '2026-10-17T12:15:00Z', 'value': null},
              {'bucket': '2026-10-17T12:30:00Z', 'value': 75.8},
            ],
          },
        ],
      });
    });
    final sub = r.watchBin().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect((await r.trends(Zone.top, Metric.moisture)).map((p) => p.value), [70.1, 75.8]);
    expect(await r.trends(Zone.bottom, Metric.moisture), isEmpty);
  });

  test('league: everyone except you; no league yet is an empty table', () async {
    final r = repo(
      (req) async => json({
        'members': [
          {'user_id': 'bot-01', 'display_name': 'Ravi', 'xp': 271, 'rank': 1, 'is_friend': true, 'streak': 4, 'color_index': 2},
          {'user_id': 'demo-user', 'display_name': 'You', 'xp': 135, 'rank': 16, 'is_you': true},
        ],
      }),
    );
    final cohort = await r.leagueCohort();
    expect(cohort.map((m) => m.name), ['Ravi']);
    expect(cohort.single.isFriend, isTrue);

    expect(await repo((req) async => json({'detail': 'not in a league'}, 404)).leagueCohort(), isEmpty);
  });

  test('a failed log does not throw into the UI', () async {
    await repo((req) async => http.Response('nope', 500)).logItem(foodById['banana_peel']!);
  });
}
