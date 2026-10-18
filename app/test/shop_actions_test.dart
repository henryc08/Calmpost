import 'package:calmpost/app/routes.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/greenhouse/greenhouse_screen.dart';
import 'package:calmpost/main.dart';
import 'package:calmpost/state/celebrations.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/ui/components.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reward_actions_test.dart' show RewardRepo;

class _ScreenRewardRepo extends RewardRepo {
  @override
  Stream<BinSnapshot> watchBin() => super.watchBin().take(1);
}

class _ScreenDemoRepo extends MockRepository {
  _ScreenDemoRepo() : super(Scenario.healthy);
  @override
  Stream<BinSnapshot> watchBin() => super.watchBin().take(1);
}

Future<void> openShop(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const CalmpostApp()));
  await tester.pump();
  Routes.greenhouse(tester.element(find.byType(Scaffold).first));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> loadShopFonts() async {
  for (final family in {
    'Manrope': ['500', '600', '700', '800'],
    'Fraunces': ['400', '500'],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final weight in family.value) {
      loader.addFont(rootBundle.load('assets/fonts/${family.key}-$weight.ttf'));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(loadShopFonts);
  testWidgets('live shop disables busy/unaffordable purchases and shows the real failure above its route', (tester) async {
    final repo = _ScreenRewardRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    await openShop(tester, c);
    final ten = tester.widget<Pressable>(find.ancestor(of: find.text('10 pulls'), matching: find.byType(Pressable)).first);
    expect(ten.onTap, isNull);
    await tester.tap(find.text('1 pull'));
    await tester.tap(find.text('1 pull'));
    await tester.pump();
    expect(repo.actions, ['pull']);
    expect(find.text('Opening Seed Packets…'), findsOneWidget);
    final one = tester.widget<Pressable>(find.ancestor(of: find.text('1 pull'), matching: find.byType(Pressable)).first);
    expect(one.onTap, isNull);
    repo.writes.single.completeError(StateError('offline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not confirm that action. Check your rewards before retrying.'), findsOneWidget);
    expect(find.text('Not enough Loam yet'), findsNothing);
    expect(find.text('Opening Seed Packets…'), findsNothing);
    expect(c.read(gameProvider).loam, 100);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('demo shop shows feedback on the pushed page and spends once per pull', (tester) async {
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_ScreenDemoRepo())]);
    addTearDown(c.dispose);
    await openShop(tester, c);
    c.read(toastProvider.notifier).show('Visible shop feedback');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Visible shop feedback'), findsOneWidget);
    final before = c.read(gameProvider).packets;
    await tester.tap(find.text('Open your Seed Packet'));
    // The immediately opened reveal may already intercept the second tap.
    await tester.tap(find.text('Open your Seed Packet'), warnIfMissed: false);
    await tester.pump();
    expect(c.read(gameProvider).packets, before - 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Collect'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Greenhouse'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Lid Lock buying state prevents rapid duplicate purchase', (tester) async {
    final repo = _ScreenRewardRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    await openShop(tester, c);
    await Scrollable.ensureVisible(tester.element(find.text('Buy')), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Buy'));
    await tester.tap(find.text('Buy'));
    await tester.pump();
    expect(find.text('Buying…'), findsOneWidget);
    expect(repo.actions, ['lid-lock']);
    repo.writes.single.complete({});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Lid Lock added. Your streak is safer.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  for (final packets in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12]) {
    testWidgets('$packets owned packets sends only a supported batch', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = RewardRepo()..packets = packets;
      final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: buildTheme(), home: const GreenhouseScreen()),
        ),
      );
      await tester.pump();
      if (packets == 0) {
        expect(find.text('Open your Seed Packet'), findsNothing);
        expect(find.text('Open 10 Seed Packets'), findsNothing);
        expect(repo.actions, isEmpty);
      } else {
        await tester.tap(find.text(packets < 10 ? 'Open your Seed Packet' : 'Open 10 Seed Packets'));
        await tester.pump();
        expect(repo.actions, ['pull']);
        expect(repo.arguments.single, {'count': packets < 10 ? 1 : 10, 'paid_with': 'packet'});
        repo.writes.single.completeError(StateError('test network failure'));
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
