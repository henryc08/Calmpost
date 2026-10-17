// Real Flutter renders: flutter test test/ui_features_visual_test.dart --dart-define=CAPTURE_REVIEW=true
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/drop_history.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/calibration/calibration_screen.dart';
import 'package:calmpost/features/history/drop_history_screen.dart';
import 'package:calmpost/features/photo/photo_screen.dart';
import 'package:calmpost/features/trunc/trunc_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/trunc_chat.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _VisualRepo extends MockRepository {
  _VisualRepo() : super(Scenario.healthy);
  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
  @override
  Future<DropHistoryPage> dropHistory({String? before, int limit = 20}) async => DropHistoryPage(
    drops: [
      PastDrop(
        id: 1,
        time: DateTime(2026, 10, 17, 14, 30),
        status: DropStatus.confirmed,
        source: 'photo',
        guesses: ['banana peel'],
        items: const [PastDropItem(label: 'Coffee grounds', grams: 110, category: 'green')],
        corrected: true,
      ),
      PastDrop(id: 2, time: DateTime(2026, 10, 17, 14), status: DropStatus.dismissed, source: 'camera', guesses: const []),
    ],
  );
}

void main() {
  testWidgets('new screens follow the app theme and render at phone size', (t) async {
    t.view.physicalSize = const Size(412 * 2, 915 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    for (final entry in jsonDecode(await rootBundle.loadString('FontManifest.json')) as List) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts']) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_VisualRepo())]);
    final boundary = GlobalKey();
    Future<void> screen(Widget widget) async {
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: widget),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      expect(t.takeException(), isNull);
      if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('../artifacts/ui-features')..createSync(recursive: true);
        await File('${dir.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await screen(const TruncScreen());
    final sending = c.read(truncChatProvider.notifier).send('test fallback');
    await t.pump(const Duration(seconds: 2));
    await sending;
    await t.pumpAndSettle();
    await capture('01-trunc');
    await screen(const PhotoScreen());
    await capture('02-phone-photo');
    await screen(const DropHistoryScreen());
    await capture('03-history');
    await screen(const CalibrationScreen());
    await t.tap(find.text('Probe 2 · Bottom'));
    await t.pumpAndSettle();
    await capture('04-calibration');
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
}
