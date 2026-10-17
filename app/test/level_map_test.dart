import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/greenhouse/pull_reveal.dart';
import 'package:calmpost/features/levels/level_map.dart';
import 'package:calmpost/data/collectibles.dart';
import 'package:calmpost/domain/gacha.dart';
import 'package:calmpost/main.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo extends MockRepository {
  _Repo() : super(Scenario.healthy);
  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
}

Future<void> settle(WidgetTester t, [int ms = 1000]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in jsonDecode(await rootBundle.loadString('FontManifest.json')) as List) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts']) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final width in [360.0, 412.0]) {
    testWidgets('Home opens level trail and claims a seed at ${width}dp', (t) async {
      t.view.physicalSize = Size(width * 2, 900 * 2);
      t.view.devicePixelRatio = 2;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_Repo())]);
      final boundary = GlobalKey();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: RepaintBoundary(key: boundary, child: const CalmpostApp()),
        ),
      );
      await settle(t);
      await t.tap(find.byKey(const ValueKey('open-level-map')));
      await settle(t);
      expect(find.text('Your growth trail'), findsOneWidget);
      expect(t.takeException(), isNull);

      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await t.runAsync(() async {
          final img = await render.toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('../artifacts/review')..createSync(recursive: true);
          await File('${dir.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }

      await capture('level-map-${width.toInt()}');
      final claim = find.byKey(const ValueKey('claim-level-1'));
      await t.ensureVisible(claim);
      await settle(t, 300);
      await t.tap(claim);
      await settle(t);
      expect(find.text('Small scraps, living soil'), findsNothing); // The label includes FIELD NOTE.
      expect(find.textContaining('FIELD NOTE'), findsOneWidget);
      expect(c.read(gameProvider).levelClaimed, contains(1));
      await capture('seed-unlock-${width.toInt()}');
      final activate = find.text('Activate seed');
      await t.ensureVisible(activate);
      await t.tap(activate);
      await settle(t);
      expect(c.read(gameProvider).activeSeed, 'sprout');
      expect(find.text('Active seed'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Done'));
      await settle(t);
      expect(find.byKey(const ValueKey('claim-level-1')), findsNothing);
      // A packet unlock also contains the lesson, with a scroll-reachable action.
      final context = t.element(find.byType(LevelMapScreen));
      // Epic and legendary descriptions are longer and must still fit at 1.3x.
      for (final seed in ['sprout', 'firefern', 'golden_sprout']) {
        showPullReveal(context, [PullOutcome(collectibleById[seed]!, isNew: true, refund: 0)]);
        await settle(t, 3000);
        expect(find.textContaining('FIELD NOTE'), findsOneWidget);
        await t.ensureVisible(find.text('Collect'));
        expect(t.takeException(), isNull);
        if (seed == 'golden_sprout') await capture('legendary-seed-${width.toInt()}');
        await t.tap(find.text('Collect'));
        await settle(t);
      }
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await t.pump();
    });
  }
}
