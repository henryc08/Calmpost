import 'dart:async';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/health_score.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/home/trunc_suggestion.dart';
import 'package:calmpost/features/log/log_screen.dart';
import 'package:calmpost/features/trunc/trunc_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/trunc_brief.dart';
import 'package:calmpost/ui/components.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'trunc_guidance_test.dart' show caseSnapshot;

final healthy = caseSnapshot({'top': 52, 'bottom': 48, 'greens': 3, 'browns': 7});
final wet = caseSnapshot({'top': 80, 'bottom': 55, 'greens': 3, 'browns': 7});
final dry = caseSnapshot({'top': 20, 'bottom': 50, 'greens': 3, 'browns': 7});
final staleWet = caseSnapshot({'top': 80, 'bottom': 55, 'greens': 3, 'browns': 7, 'stale': true});

BinHealth health(BinSnapshot s) {
  final b = computeHealth(s);
  return BinHealth(s, b, moodFor(s, b.total));
}

Widget app(BinSnapshot s, Widget child) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(MockRepository(Scenario.healthy)),
    binProvider.overrideWith((ref) => Stream.value(s)),
    truncBriefProvider.overrideWith((ref) async => null),
  ],
  child: MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: child))),
);

void main() {
  test('only fresh readings in a bad state raise the alert', () {
    expect(health(healthy).mood, isNot(anyOf(BinMood.wet, BinMood.dry, BinMood.struggling)));
    expect(binNeedsHelp(health(healthy)), false);
    expect(binNeedsHelp(health(wet)), true);
    expect(binNeedsHelp(health(dry)), true);
    expect(binNeedsHelp(health(staleWet)), false, reason: 'never alarm on old data');
    expect(binNeedsHelp(null), false, reason: 'no bin yet');
  });

  test('a low score alone raises it', () {
    final s = health(healthy);
    final struggling = BinHealth(s.snapshot, s.breakdown, BinMood.struggling);
    expect(binNeedsHelp(struggling), true);
    expect(binNeedsHelp(BinHealth(s.snapshot, s.breakdown, BinMood.fair)), false);
  });

  for (final (name, s, shown) in [('healthy', healthy, false), ('too wet', wet, true), ('stale', staleWet, false)]) {
    testWidgets('Home Trunc link: badge ${shown ? 'shown' : 'hidden'} when $name', (t) async {
      final semantics = t.ensureSemantics();
      await t.pumpWidget(app(s, TruncSuggestion(snapshot: s)));
      await t.pump();
      await t.pump();
      expect(find.text('Ask Trunc a specific question'), findsOneWidget);
      expect(find.byType(AlertBadge), shown ? findsOneWidget : findsNothing);
      if (shown) expect(find.bySemanticsLabel(RegExp('Your bin needs help')), findsOneWidget);
      expect(t.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('Log Ask Trunc button gets the badge and still opens Trunc', (t) async {
    t.view.physicalSize = const Size(360, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(MockRepository(Scenario.healthy)),
          binProvider.overrideWith((ref) => Stream.value(wet)),
        ],
        child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: LogScreen())),
      ),
    );
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    final button = find.text('Ask Trunc');
    expect(button, findsOneWidget);
    expect(find.byType(AlertBadge), findsOneWidget);
    // The badge sits right next to the button, on the same row.
    final gap = t.getTopLeft(find.byType(AlertBadge)).dx - t.getTopRight(find.ancestor(of: button, matching: find.byType(PillButton))).dx;
    expect(gap, inInclusiveRange(0, 16));
    await t.ensureVisible(button);
    await t.pump();
    await t.tap(button);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(TruncScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    // Let the Log screen's own timers finish before the test ends.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 2));
  });

  test('badge goes away once the bin recovers', () async {
    final readings = StreamController<BinSnapshot>();
    final c = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(MockRepository(Scenario.healthy)),
      binProvider.overrideWith((ref) => readings.stream),
    ]);
    addTearDown(c.dispose);
    addTearDown(readings.close);
    final sub = c.listen(binNeedsHelpProvider, (_, _) {});
    Future<bool> after(BinSnapshot s) async {
      readings.add(s);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return sub.read();
    }
    expect(sub.read(), false, reason: 'no reading yet');
    expect(await after(wet), true);
    expect(await after(healthy), false);
    expect(await after(dry), true);
  });
}
