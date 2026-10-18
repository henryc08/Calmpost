import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/home/readings_row.dart';
import 'package:calmpost/features/layers/layers_screen.dart';
import 'package:calmpost/features/layers/moisture_map.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'api_repository_test.dart' as fixture;

BinSnapshot moistureOnly() {
  final j = fixture.live(bottomMeasured: true);
  j['time'] = DateTime.now().toUtc().toIso8601String();
  (j['layers'] as List)[1]['temp_c'] = null;
  return snapshotFromJson(j);
}

class BottomRepo extends MockRepository {
  BottomRepo() : super(Scenario.healthy);
  bool fail = false;
  bool withHistory = false;
  final requests = <(Zone, Metric)>[];
  @override
  Stream<BinSnapshot> watchBin() => Stream.value(moistureOnly());
  @override
  Future<List<TrendPoint>> trends(Zone zone, Metric metric) async {
    requests.add((zone, metric));
    if (fail) throw Exception('network');
    if (withHistory) {
      return [
        TrendPoint(DateTime.now().subtract(const Duration(hours: 1)), zone == Zone.bottom ? 70 : 20),
        TrendPoint(DateTime.now(), zone == Zone.bottom ? 80 : 30),
      ];
    }
    return [];
  }
}

Future<void> settle(WidgetTester t) async {
  // LiveDot intentionally animates forever while readings are fresh.
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    for (final family in ['Manrope', 'Fraunces']) {
      final loader = FontLoader(family)..addFont(rootBundle.load('assets/fonts/$family-${family == 'Manrope' ? '500' : '400'}.ttf'));
      await loader.load();
    }
  });
  test('bottom moisture does not imply temperature or calibration', () {
    final s = moistureOnly();
    expect(s.bottomMeasured, true);
    expect(s.bottomTemperatureMeasured, false);
    expect(s.calibrated(Zone.top), true);
    expect(s.calibrated(Zone.bottom), false);
  });
  testWidgets('home does not show an invented bottom temperature', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ReadingsRow(s: moistureOnly(), onOpen: (_) {}),
        ),
      ),
    );
    expect(find.text('76% / 48%'), findsOneWidget);
    expect(find.text('22°'), findsNothing);
  });
  testWidgets('two moisture probes, separate histories, one temperature; errors retry', (t) async {
    t.view.physicalSize = const Size(360, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = BottomRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: LayersScreen()),
        ),
      ),
    );
    await settle(t);
    expect(find.text('Top layer'), findsNothing);
    expect(find.text('Bottom layer'), findsNothing);
    expect(find.byType(MoistureMap), findsOneWidget);
    expect(find.text('76%'), findsWidgets);
    expect(find.text('48%'), findsWidgets);
    expect(find.textContaining('Probe 2 uncalibrated'), findsOneWidget);
    await t.ensureVisible(find.text('Probe 2 history'));
    await t.tap(find.text('Probe 2 history'));
    await settle(t);
    expect(find.textContaining('No Probe 2 history yet'), findsOneWidget);
    expect(repo.requests, contains((Zone.bottom, Metric.moisture)));
    repo.withHistory = true;
    c.invalidate(trendProvider((Zone.bottom, Metric.moisture)));
    await settle(t);
    expect(find.text('80%'), findsWidgets);
    expect(find.textContaining('No Probe 2 history yet'), findsNothing);
    await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(t);
    await t.tap(find.text('Temperature'));
    await settle(t);
    expect(find.text('31.0 °C'), findsOneWidget);
    expect(find.text('Ambient air: 22.0 °C'), findsOneWidget);
    expect(find.text('23.0 °C'), findsNothing);
    expect(repo.requests, contains((Zone.top, Metric.temperature)));
    expect(repo.requests, isNot(contains((Zone.bottom, Metric.temperature))));
    repo.fail = true;
    c.invalidate(trendProvider((Zone.top, Metric.temperature)));
    await settle(t);
    expect(find.text('Retry trend'), findsOneWidget);
    repo.fail = false;
    await t.ensureVisible(find.text('Retry trend'));
    await settle(t);
    await t.tap(find.text('Retry trend'));
    await settle(t);
    expect(find.text('Retry trend'), findsNothing);
    await t.pump(const Duration(seconds: 2));
    await settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('map separates wet and dry; missing and stale probes stay unknown', (t) async {
    Future<void> render(Map<String, dynamic> j) => t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: MoistureMap(snapshot: snapshotFromJson(j))),
      ),
    );
    final j = fixture.live(topMoisture: 25, bottomMeasured: true);
    j['time'] = DateTime.now().toUtc().toIso8601String();
    (j['layers'] as List)[1]['moisture_pct'] = 80.0;
    await render(j);
    expect(find.text('Below guide'), findsOneWidget);
    expect(find.text('Above guide'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    j['stale'] = true;
    await render(j);
    expect(find.text('Last reading · stale'), findsNWidgets(2));
    expect(find.text('Above guide'), findsNothing);
    (j['layers'] as List)[1]['moisture_pct'] = null;
    (j['layers'] as List)[1]['measured'] = false;
    await render(j);
    expect(find.text('Not measured'), findsOneWidget);
    expect(find.text('80%'), findsNothing);
    (j['layers'] as List)[0] = Map<String, dynamic>.from((j['layers'] as List)[0] as Map)..['moisture_pct'] = null;
    (j['layers'] as List)[0]['measured'] = false;
    await render(j);
    expect(find.text('Not measured'), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });

  testWidgets('temperature never borrows bottom or ambient when the compost probe is absent', (t) async {
    final j = fixture.live(bottomMeasured: true);
    (j['layers'] as List)[0] = Map<String, dynamic>.from((j['layers'] as List)[0] as Map)..['temp_c'] = null;
    final c = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(BottomRepo()), binProvider.overrideWith((ref) => Stream.value(snapshotFromJson(j)))],
    );
    addTearDown(c.dispose);
    c.read(sensorMetricProvider.notifier).state = Metric.temperature;
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: LayersScreen()),
        ),
      ),
    );
    await settle(t);
    expect(find.text('Not measured · check the sensor connection'), findsOneWidget);
    expect(find.text('Ambient air: 22.0 °C'), findsOneWidget);
    expect(find.text('23.0 °C'), findsNothing);
    await t.tap(find.text('View air · CO₂'));
    await settle(t);
    expect(find.text('3600 ppm'), findsOneWidget);
    expect(c.read(sensorMetricProvider), Metric.co2);
    expect(t.takeException(), isNull);
  });

  testWidgets('sensor loading and connection error are visible and retry recovers', (t) async {
    var fail = true;
    final c = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(BottomRepo()),
        binProvider.overrideWith((ref) => fail ? Stream.error(Exception('offline')) : Stream.value(moistureOnly())),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: LayersScreen()),
        ),
      ),
    );
    expect(find.text('Waiting for sensor readings…'), findsOneWidget);
    await settle(t);
    expect(find.text("Can't reach the bin."), findsOneWidget);
    fail = false;
    await t.tap(find.text('Retry readings'));
    await settle(t);
    expect(find.byType(MoistureMap), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
