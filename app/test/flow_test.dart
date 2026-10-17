import 'package:calmpost/data/calmpost_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/main.dart';
import 'package:calmpost/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock bin that emits one reading and stops (no timers left behind in tests).
class _OneShotRepo extends MockRepository {
  _OneShotRepo(super.scenario);

  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
}

void main() {
  testWidgets('core loop: log, streak, quest claim, tabs, harvest', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [repositoryProvider.overrideWith((ref) => _OneShotRepo(ref.watch(scenarioProvider)) as CalmpostRepository)]);
    addTearDown(container.dispose);

    Future<void> settle([int ms = 1200]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> tapText(String text) async {
      final f = find.text(text).last;
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f, warnIfMissed: false);
      await settle();
    }

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CalmpostApp(onboarded: true)));
    await settle();
    expect(find.text('Kitchen bin'), findsOneWidget);

    // Log a tip item (veggie peels is one of Wren's suggestions when balanced).
    await tester.tap(find.bySemanticsLabel('Log a scrap'));
    await settle();
    expect(find.text('What are you adding?'), findsOneWidget);
    await tapText('Veggie peels');
    expect(find.textContaining('this is one of Wren'), findsOneWidget);
    await tapText('ADD IT');

    // First care action of the day: streak celebration.
    expect(find.text('day streak!'), findsOneWidget);
    await tapText('CONTINUE');
    await settle(3000);

    // The follow quest is done: claim its chest.
    await tester.scrollUntilVisible(find.text('CLAIM'), 300, scrollable: find.byType(Scrollable).first);
    await tapText('CLAIM');
    expect(find.text('Quest complete!'), findsOneWidget);
    await settle(2000);
    await tapText('CONTINUE');

    // Tabs render.
    await tester.tap(find.bySemanticsLabel('Leagues'));
    await settle();
    expect(find.text('Fern League'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Journey'));
    await settle();
    expect(find.text('Journey'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Profile'));
    await settle();
    expect(find.text('YOUR CLIMATE IMPACT'), findsOneWidget);

    // Bin finishes: ready celebration, then harvest.
    container.read(scenarioProvider.notifier).state = Scenario.ready;
    await settle(2000);
    expect(find.text('Ready!'), findsOneWidget);
    await tapText('HARVEST NOW');
    await settle(1500);
    expect(find.text('Harvest #3!'), findsOneWidget);
    await tapText('CONTINUE');

    // Tear down and let delayed timers (blinks, toasts) run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('no overflows at 360dp with large text', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer(overrides: [repositoryProvider.overrideWith((ref) => _OneShotRepo(ref.watch(scenarioProvider)) as CalmpostRepository)]);
    addTearDown(container.dispose);

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CalmpostApp(onboarded: true)));
    await settle();
    for (final scenario in Scenario.values.take(3)) {
      container.read(scenarioProvider.notifier).state = scenario;
      await settle();
      for (final tab in ['Journey', 'Leagues', 'Profile', 'Home']) {
        await tester.tap(find.bySemanticsLabel(tab));
        await settle();
        // Scroll through the whole tab so lazily-built cards lay out too.
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 8; i++) {
          await tester.drag(scrollable, const Offset(0, -500), warnIfMissed: false);
          await settle();
        }
      }
    }
    await tester.tap(find.bySemanticsLabel('Log a scrap'));
    await settle();
    await tester.tap(find.text('Banana peel').first);
    await settle();
    await settle();

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
