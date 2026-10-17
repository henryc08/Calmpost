// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:calmpost/data/collectibles.dart';
import 'package:calmpost/features/greenhouse/greenhouse_screen.dart';
import 'package:calmpost/state/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  const families = {
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

  // Pulls are random, so which names show used to vary by run. Own everything so
  // every name (including the longest) is on screen at once.
  testWidgets('collection fits every name at 360dp with 1.3x text', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final game = container.read(gameProvider.notifier);
    game.state = game.state.copyWith(owned: {for (final c in collectibles) c.id: 2});

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: GreenhouseScreen())));
    await tester.pump(const Duration(seconds: 1));
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 6; i++) {
      await tester.drag(scrollable, const Offset(0, -400), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
