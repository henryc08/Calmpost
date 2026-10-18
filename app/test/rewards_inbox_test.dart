import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/rewards/rewards_screen.dart';
import 'package:calmpost/state/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening a crate removes it with its origin and logs it first in history', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final before = c.read(gameProvider);
    expect(before.crateFrom.length, before.crates.length);
    final o = c.read(gameProvider.notifier).openCrate(0)!;
    final after = c.read(gameProvider);
    expect(after.crates.length, before.crates.length - 1);
    expect(after.crateFrom.length, after.crates.length);
    expect(after.rewardLog.first.kind, RewardKind.crateOpened);
    expect(after.rewardLog.first.title, 'Opened ${crateLabel(o.tier)}');
  });

  test('pulling packets is logged', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(gameProvider.notifier).pull(1, fromPackets: true);
    expect(c.read(gameProvider).rewardLog.first.kind, RewardKind.packetsOpened);
  });

  test('when labels', () {
    final now = DateTime(2026, 10, 17, 12); // a Saturday
    expect(whenLabel(now, now: now), 'Now');
    expect(whenLabel(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
    expect(whenLabel(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
    expect(whenLabel(DateTime(2026, 10, 12, 9), now: now), 'Mon');
    expect(whenLabel(DateTime(2026, 9, 1), now: now), '1/9');
  });

  testWidgets('inbox lists waiting crates and opens one into history', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: RewardsScreen(openGreenhouse: (_) async {})),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sprout crate'), findsOneWidget);
    expect(find.text('From Daily goal'), findsOneWidget);
    await tester.tap(find.text('Open').first);
    await tester.pump(const Duration(seconds: 2)); // the reveal unlocks Collect after 900 ms
    await tester.tap(find.text('Collect'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('Opened Sprout crate'), findsNWidgets(2)); // the new one + the demo history's
    expect(find.text('From Daily goal'), findsNothing);
    // Let the reveal's and entrance animations' timers finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
