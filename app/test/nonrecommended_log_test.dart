import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/features/log/verdict_sheet.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.3, 2.0]) {
    testWidgets('non-recommended banana remains loggable at text scale $scale', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      for (final entry in {
        'Manrope': ['500', '600', '700', '800'],
        'Fraunces': ['400', '500'],
      }.entries) {
        final loader = FontLoader(entry.key);
        for (final w in entry.value) {
          loader.addFont(rootBundle.load('assets/fonts/${entry.key}-$w.ttf'));
        }
        await loader.load();
      }
      final repo = MockRepository(Scenario.tooWet);
      await t.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(onPressed: () => showVerdictSheet(context, foodById['banana_peel']!), child: const Text('Open')),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Add it carefully'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Add it carefully').hitTestable(), findsOneWidget);
      final container = ProviderScope.containerOf(t.element(find.text('Add it carefully')));
      expect(container.read(suggestionProvider)!.add.any((f) => f.id == 'banana_peel'), isFalse);
      await t.tap(find.text('Add it carefully'));
      await t.pump(const Duration(seconds: 1));
      expect(container.read(gameProvider).logs.first.item.id, 'banana_peel');
      expect(container.read(gameProvider).logs.first.added, isTrue);
      expect(container.read(gameProvider).logs.first.xp, 5); // volume, no care bonus
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 4));
    });
  }
}
