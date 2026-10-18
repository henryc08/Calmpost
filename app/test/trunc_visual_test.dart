// Real Flutter renders, not mockups: --dart-define=CAPTURE_REVIEW=true
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/main.dart';
import 'package:calmpost/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _VisualRepo extends MockRepository {
  _VisualRepo() : super(Scenario.tooWet);
  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
}

void main() {
  testWidgets('Home Trunc opens a current-bin apples answer at Android size', (t) async {
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
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_VisualRepo())]);
    addTearDown(c.dispose);
    final boundary = GlobalKey();
    Future<void> settle([int ms = 2000]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> capture(String name) async {
      expect(t.takeException(), isNull);
      if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('../artifacts/trunc')..createSync(recursive: true);
        await File('${dir.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: RepaintBoundary(key: boundary, child: const CalmpostApp()),
      ),
    );
    await settle();
    await Scrollable.ensureVisible(t.element(find.text('For your bin, right now')), alignment: .1);
    await settle(300);
    await capture('01-home-suggestion');
    await t.ensureVisible(find.text('Ask Trunc a specific question'));
    await t.tap(find.text('Ask Trunc a specific question'));
    await settle(500);
    await t.tap(find.text('Should I add more apples to this compost?'));
    await settle();
    expect(find.textContaining('Hold off on apples'), findsOneWidget);
    await capture('02-apples-answer');
    t.view.physicalSize = const Size(360 * 2, 740 * 2);
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    await settle(300);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });
}
