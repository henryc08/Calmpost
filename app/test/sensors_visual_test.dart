// Actual Flutter renders: flutter test test/sensors_visual_test.dart --dart-define=CAPTURE_REVIEW=true
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/layers/layers_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'api_repository_test.dart' as fixture;
import 'bottom_probe_ui_test.dart' show settle;

class _SensorRepo extends MockRepository {
  _SensorRepo() : super(Scenario.healthy);
  @override
  Stream<BinSnapshot> watchBin() {
    final j = fixture.live(topMoisture: 32, bottomMeasured: true);
    j['time'] = DateTime.now().toUtc().toIso8601String();
    (j['layers'] as List)[1]['moisture_pct'] = 71.0;
    (j['layers'] as List)[1]['temp_c'] = null;
    return Stream.value(snapshotFromJson(j));
  }
}

void main() {
  testWidgets('metric views fit a small Android screen with large text and render previews', (t) async {
    t.view.physicalSize = const Size(412 * 2, 915 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    for (final entry in jsonDecode(await rootBundle.loadString('FontManifest.json')) as List) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts']) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_SensorRepo())]);
    addTearDown(c.dispose);
    final boundary = GlobalKey();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            home: const Scaffold(body: LayersScreen()),
          ),
        ),
      ),
    );
    await settle(t);
    Future<void> capture(String name) async {
      expect(t.takeException(), isNull);
      if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('../artifacts/sensors')..createSync(recursive: true);
        await File('${dir.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('01-moisture');
    await t.tap(find.text('Temperature'));
    await settle(t);
    await capture('02-temperature');
    t.view.physicalSize = const Size(360 * 2, 740 * 2);
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    for (final metric in Metric.values) {
      c.read(sensorMetricProvider.notifier).state = metric;
      await settle(t);
      final scroll = find.byType(Scrollable).first;
      for (var i = 0; i < 4; i++) {
        await t.drag(scroll, const Offset(0, -400));
        await settle(t);
        expect(t.takeException(), isNull);
      }
      await t.drag(scroll, const Offset(0, 5000));
      await settle(t);
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
