import 'package:calmpost/data/calmpost_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/main.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock bin that emits one reading and stops (no timers left behind).
class _OneShotRepo extends MockRepository {
  _OneShotRepo(super.scenario);

  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
}

ProviderContainer _container() =>
    ProviderContainer(overrides: [repositoryProvider.overrideWith((ref) => _OneShotRepo(ref.watch(scenarioProvider)) as CalmpostRepository)]);

Future<void> _settle(WidgetTester tester, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _loadFonts() async {
  final families = {
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

  testWidgets('home: check-in lights the calendar and quests pay out', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CalmpostApp()));
    await _settle(tester);
    expect(find.text('BIN HEALTH'), findsOneWidget);
    expect(find.text('NEXT BEST ACTION'), findsOneWidget);

    // Opening Layers checks on the bin: streak extends, quest completes.
    await tester.tap(find.bySemanticsLabel('Layers'));
    await _settle(tester);
    expect(container.read(gameProvider).caredToday, isTrue);
    expect(container.read(gameProvider).streak.days, 7);

    await tester.tap(find.bySemanticsLabel('Home'));
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('Claim'), 300, scrollable: find.byType(Scrollable).first);
    final before = container.read(gameProvider).loam;
    await tester.tap(find.text('Claim'));
    await _settle(tester);
    expect(container.read(gameProvider).loam, before + 10);
    expect(find.text('Done today'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('home: no overflows at 360dp with large text', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CalmpostApp()));
    for (final s in Scenario.values) {
      container.read(scenarioProvider.notifier).state = s;
      await _settle(tester);
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 6; i++) {
        await tester.drag(scrollable, const Offset(0, -500), warnIfMissed: false);
        await _settle(tester, 400);
      }
      for (var i = 0; i < 6; i++) {
        await tester.drag(scrollable, const Offset(0, 500), warnIfMissed: false);
      }
      await _settle(tester, 400);
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
