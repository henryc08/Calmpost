import 'package:calmpost/features/greenhouse/greenhouse_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reward_actions_test.dart' show RewardRepo;

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
