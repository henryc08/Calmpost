import 'dart:convert';
import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/calibration.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/calibration/calibration_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class CalibrationRepo extends MockRepository {
  CalibrationRepo() : super(Scenario.healthy);
  bool fail = true;
  final calls = <(int, int, int, bool)>[];
  @override
  Future<CalibrationResult> calibrateProbe({required int probe, required int dry, required int wet, bool backfill = false}) async {
    calls.add((probe, dry, wet, backfill));
    if (fail) throw Exception('connection');
    return super.calibrateProbe(probe: probe, dry: dry, wet: wet, backfill: backfill);
  }

  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
}

void main() {
  setUpAll(() async {
    for (final family in ['Manrope', 'Fraunces']) {
      await (FontLoader(family)..addFont(rootBundle.load('assets/fonts/$family-${family == 'Manrope' ? '500' : '400'}.ttf'))).load();
    }
  });
  test('calibration validates raw counts and explicitly scopes the authenticated API write', () async {
    expect(calibrationError(2, 600, 600), isNotNull);
    expect(calibrationError(2, 70000, 300), isNotNull);
    expect(calibrationError(3, 600, 300), isNotNull);
    expect(calibrationError(1, 300, 600), isNull);
    final r = ApiRepository(
      const ApiConfig(baseUrl: 'http://bin.test', apiKey: '', token: 'session'),
      client: MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer session');
        expect(req.url.path, '/bins/bin-001/calibration');
        expect(jsonDecode(req.body), {'probe': 2, 'moisture_raw_dry': 600, 'moisture_raw_wet': 300, 'backfill': false});
        return http.Response(jsonEncode({'probe': 2, 'moisture_raw_dry': 600, 'moisture_raw_wet': 300, 'readings_recomputed': 0}), 200);
      }),
    );
    addTearDown(r.close);
    expect((await r.calibrateProbe(probe: 2, dry: 600, wet: 300)).probe, 2);
  });
  test('mock calibration isolates probe flags', () async {
    final r = MockRepository(Scenario.healthy);
    final initial = await r.watchBin().first;
    await r.calibrateProbe(probe: 1, dry: 600, wet: 300);
    expect((await r.watchBin().first).bottomMoistureCalibrated, initial.bottomMoistureCalibrated);
    await r.calibrateProbe(probe: 2, dry: 900, wet: 200);
    final after = await r.watchBin().first;
    expect(after.bottomMoistureCalibrated, true);
    expect(after.moistureCalibrated, initial.moistureCalibrated);
    expect(after.topMoisture, closeTo(initial.topMoisture, 1)); // Normal simulated sensor noise only.
  });
  testWidgets('calibration validates, retries without losing inputs and clears them when changing probe', (t) async {
    t.view.physicalSize = const Size(360, 900);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = CalibrationRepo();
    await t.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(theme: buildTheme(), home: const CalibrationScreen()),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Probe 2 · Bottom'));
    await t.pumpAndSettle();
    Future<void> save() async {
      await t.ensureVisible(find.text('Save probe 2 calibration'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save probe 2 calibration'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
    }

    await save();
    expect(repo.calls, isEmpty);
    await t.enterText(find.byKey(const ValueKey('Dry reference')), '600');
    await t.enterText(find.byKey(const ValueKey('Wet reference')), '300');
    await save();
    expect(find.textContaining('Your inputs are kept'), findsOneWidget);
    expect(repo.calls.single, (2, 600, 300, false));
    repo.fail = false;
    await save();
    expect(find.text('Probe 2 calibration saved'), findsOneWidget);
    expect(repo.calls, hasLength(2));
    await t.ensureVisible(find.text('Probe 1 · Top'));
    await t.pumpAndSettle();
    await t.tap(find.text('Probe 1 · Top'));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byKey(const ValueKey('Dry reference'))).controller!.text, isEmpty);
    expect(find.text('Probe 2 calibration saved'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
