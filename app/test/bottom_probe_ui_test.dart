import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/home/readings_row.dart';
import 'package:calmpost/features/layers/layers_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'api_repository_test.dart' as fixture;

BinSnapshot moistureOnly() {
  final j = fixture.live(bottomMeasured: true);
  (j['layers'] as List)[1]['temp_c'] = null;
  return snapshotFromJson(j);
}

class BottomRepo extends MockRepository {
  BottomRepo() : super(Scenario.healthy);
  bool fail = false;
  @override
  Stream<BinSnapshot> watchBin() => Stream.value(moistureOnly());
  @override
  Future<List<TrendPoint>> trends(Zone zone, Metric metric) async {
    if (fail) throw Exception('network');
    return [];
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
    expect(find.text('48'), findsOneWidget);
    expect(find.text('22°'), findsNothing);
  });
  testWidgets('bottom empty history and absent temperature are explicit; errors retry', (t) async {
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
    await t.pumpAndSettle();
    await t.tap(find.text('Bottom layer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Bottom-layer history is not available'), findsOneWidget);
    expect(find.textContaining('temperature not measured'), findsOneWidget);
    await t.tap(find.text('Temperature'));
    await t.pumpAndSettle();
    expect(find.text('NOT MEASURED'), findsOneWidget);
    expect(find.text('22.0'), findsNothing);
    repo.fail = true;
    c.invalidate(trendProvider((Zone.bottom, Metric.temperature)));
    await t.pumpAndSettle();
    expect(find.text('Retry trend'), findsOneWidget);
    repo.fail = false;
    await t.ensureVisible(find.text('Retry trend'));
    await t.pumpAndSettle();
    await t.tap(find.text('Retry trend'));
    await t.pumpAndSettle();
    expect(find.text('Retry trend'), findsNothing);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
