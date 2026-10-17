import 'package:calmpost/ui/info_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('info dot opens its sheet, closes on Got it, and marks itself seen', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: Center(child: InfoDot(InfoTip.league)))),
    ));

    expect(container.read(seenTipsProvider), isEmpty);
    await tester.tap(find.byType(InfoDot));
    await tester.pumpAndSettle();
    expect(find.text(InfoTip.league.title), findsOneWidget);
    expect(find.textContaining('top 7 move up'), findsOneWidget);
    expect(container.read(seenTipsProvider), {InfoTip.league});

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text(InfoTip.league.title), findsNothing);
  });

  test('the app keeps its hints few', () {
    expect(InfoTip.values.length, lessThanOrEqualTo(7));
  });
}
