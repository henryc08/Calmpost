// End-to-end against a running backend (and the Tiger database behind it).
// Skipped unless API_URL is given:
//
//   flutter test test/live_api_test.dart --dart-define=API_URL=http://127.0.0.1:8000 --dart-define=API_KEY=<APP_API_KEY>
//
// Read-only except for the scrap check (which stores its answer, as the app does).
import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/domain/health_score.dart';
import 'package:calmpost/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final skip = ApiConfig.configured ? false : 'pass --dart-define=API_URL=... to run against a live backend';

  test('live bin: readings, trends, scrap check and league through the real API', () async {
    final repo = ApiRepository(ApiConfig.fromEnvironment());
    addTearDown(repo.close);

    final s = await repo.watchBin().first;
    final h = computeHealth(s);
    // ignore: avoid_print
    print(
      'live: top ${s.topMoisture.toStringAsFixed(1)}% ${s.topTemp.toStringAsFixed(1)}°C · '
      'bottom ${s.bottomMeasured ? '${s.bottomMoisture.round()}%' : 'not measured'} · '
      'CO₂ ${s.co2.round()} ppm · health ${h.total} (${moodLabel(moodFor(s, h.total))}) · '
      'stage ${s.topStage.name} · stale ${s.stale}',
    );
    expect(s.topMoisture, inInclusiveRange(0, 100));
    expect(DateTime.now().difference(s.time).inDays, lessThan(30));

    final trend = await repo.trends(Zone.top, Metric.moisture);
    // ignore: avoid_print
    print('trend: ${trend.length} points over 24 h');
    expect(trend, isNotEmpty);
    if (!s.bottomMeasured) expect(await repo.trends(Zone.bottom, Metric.moisture), isEmpty);

    final advice = await repo.checkItem(foodById['banana_peel']!);
    // ignore: avoid_print
    print('banana peel: ${advice.verdict.name} · ${advice.headline} · pair with ${advice.pairWith.map((f) => f.name).join(', ')}');
    expect(advice.reason, isNotEmpty);

    final cohort = await repo.leagueCohort();
    // ignore: avoid_print
    print('league: ${cohort.length} others, top ${cohort.isEmpty ? '-' : '${cohort.first.name} ${cohort.first.xp} XP'}');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 1)));
}
