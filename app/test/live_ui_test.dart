import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/calmpost_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/main.dart';
import 'package:calmpost/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the real bin looks like today: one probe (top), a bin that stopped
/// reporting 20 minutes ago, and a brand-new three-person league.
class _LiveShapedRepo extends MockRepository {
  _LiveShapedRepo() : super(Scenario.healthy);

  @override
  Stream<BinSnapshot> watchBin() => Stream.value(
    snapshotFromJson({
      'time': DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String(),
      'stale': true,
      'layers': [
        {'layer': 'top', 'measured': true, 'moisture_pct': 47.0, 'temp_c': 30.0, 'stage': 'active'},
        {'layer': 'bottom', 'measured': false, 'moisture_pct': null, 'temp_c': null, 'stage': 'started'},
      ],
      'air': {'co2_ppm': 1800.0, 'co2_slope_per_day': 1.0, 'ambient_temp_c': 21.0},
      'greens_7d': 3.0,
      'browns_7d': 6.0,
      'healthy_hours_today': 2.0,
    }),
  );

  @override
  Future<List<TrendPoint>> trends(Zone zone, Metric metric) async => zone == Zone.bottom ? const [] : super.trends(zone, metric);

  @override
  Future<List<LeagueMember>> leagueCohort() async => const [
    LeagueMember(name: 'Ravi', xp: 271, colorIndex: 1),
    LeagueMember(name: 'Nils', xp: 12, colorIndex: 2, isFriend: true),
  ];
}

class _UnreachableRepo extends MockRepository {
  _UnreachableRepo() : super(Scenario.healthy);

  @override
  Stream<BinSnapshot> watchBin() => Stream.error(ApiException('GET /bins/bin-001/live', 503, 'down'));
}

Future<void> _settle(WidgetTester tester, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _loadFonts() async {
  final families = {
    'Manrope': ['500', '600', '700', '800'],
    'Fraunces': ['400', '500'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final w in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/${e.key}-$w.ttf'));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('live bin: stale age, unmeasured bottom, small league; every tab fits at 360dp', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(overrides: [repositoryProvider.overrideWith((ref) => _LiveShapedRepo() as CalmpostRepository)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CalmpostApp()));
    await _settle(tester);
    expect(find.text('   SEEN 20 MIN AGO'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);

    await tester.scrollUntilVisible(find.text('BOTTOM'), 300, scrollable: find.byType(Scrollable).first);
    await _settle(tester, 300);
    expect(find.text('not measured'), findsOneWidget);

    for (final tab in AppTab.values) {
      container.read(tabProvider.notifier).state = tab;
      await _settle(tester, 600);
      final scrollable = find.byType(Scrollable).hitTestable().first;
      for (var i = 0; i < 6; i++) {
        await tester.drag(scrollable, const Offset(0, -500), warnIfMissed: false);
        await _settle(tester, 300);
      }
    }

    // Layers, bottom zone: shown as not measured, never a number.
    container.read(tabProvider.notifier).state = AppTab.layers;
    await _settle(tester, 600);
    await tester.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, 3000), warnIfMissed: false);
    await _settle(tester, 300);
    await tester.tap(find.text('Bottom layer').first);
    await _settle(tester, 600);
    expect(find.text('NOT MEASURED'), findsOneWidget);
    expect(find.textContaining('no probe here yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('unreachable backend: Home says so and offers demo data', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [repositoryProvider.overrideWith((ref) => _UnreachableRepo() as CalmpostRepository)]);
    addTearDown(container.dispose);
    container.read(dataSourceProvider.notifier).state = DataSource.live;

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CalmpostApp()));
    await _settle(tester);
    expect(find.text("Can't reach the bin"), findsOneWidget);
    await tester.tap(find.text('Use demo data'));
    await _settle(tester, 300);
    expect(container.read(dataSourceProvider), DataSource.mock);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
