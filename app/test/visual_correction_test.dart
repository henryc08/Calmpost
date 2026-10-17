// Actual Flutter-rendered phone screenshots, not design mockups.
// flutter test test/visual_correction_test.dart --dart-define=CAPTURE_REVIEW=true
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/drop/drop_sheet.dart';
import 'package:calmpost/main.dart';
import 'package:calmpost/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo extends MockRepository {
  _Repo() : super(Scenario.tooDry) {
    dropDelay = const Duration(seconds: 5);
  }
  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
}

Future<void> settle(WidgetTester t, [int ms = 1000]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('visual walkthrough: Gemini banana mistake corrected to coffee grounds', (t) async {
    t.view.physicalSize = const Size(412 * 2, 915 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts']) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    final container = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_Repo())]);
    final boundary = GlobalKey();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: boundary, child: const CalmpostApp()),
      ),
    );
    await settle(t);
    Future<void> capture(String name) async {
      expect(t.takeException(), isNull);
      if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('../artifacts/review')..createSync(recursive: true);
        await File('${dir.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    Finder sheet(Finder f) => find.descendant(of: find.byType(DropSheet), matching: f);
    Future<void> tap(Finder f) async {
      await t.ensureVisible(f);
      await settle(t, 300);
      await t.tap(f);
      await settle(t, 500);
    }

    await t.tap(find.text('Drop something in'));
    await settle(t);
    await capture('01-camera-watching');
    await settle(t, 5000);
    expect(sheet(find.text('Is this right?')), findsOneWidget);
    await capture('02-gemini-wrong-guess');
    await tap(sheet(find.text('Banana peel')));
    await t.enterText(sheet(find.byType(TextField)), 'coffee');
    await settle(t, 300);
    await tap(sheet(find.text('Coffee grounds')));
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(t, 400);
    await t.ensureVisible(sheet(find.text('Is this right?')));
    await settle(t, 400);
    await capture('03-corrected-item-and-amount');
    await tap(sheet(find.text('Save')));
    await settle(t);
    expect(sheet(find.text('LOGGED')), findsOneWidget);
    await capture('04-compost-saved');
    await t.pumpWidget(const SizedBox());
    container.dispose();
    await t.pump(const Duration(seconds: 5));
  });
}
