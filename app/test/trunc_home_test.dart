import 'dart:async';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/domain/trunc_guidance.dart';
import 'package:calmpost/features/home/trunc_suggestion.dart';
import 'package:calmpost/features/trunc/trunc_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/trunc_brief.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'trunc_guidance_test.dart' show caseSnapshot;

class BriefRepo extends MockRepository {
  BriefRepo() : super(Scenario.tooWet);
  final calls = <(String, bool, int)>[];
  final pending = <Completer<TruncReply>>[];
  @override
  Future<TruncReply> askTrunc(String message, {List<TruncTurn> history = const [], bool includePhotos = true}) {
    calls.add((message, includePhotos, history.length));
    final c = Completer<TruncReply>();
    pending.add(c);
    return c.future;
  }
}

final wet = caseSnapshot({'top': 76, 'bottom': 55, 'greens': 3, 'browns': 7});
final dry = caseSnapshot({'top': 25, 'bottom': 50, 'greens': 3, 'browns': 7});
TruncReply answer(BinNeed need, String text) => TruncReply(
  reply: text,
  model: 'gemini-test',
  onTopic: true,
  usedReadings: true,
  context: TruncContext(readingsAt: DateTime.now()),
  need: need,
);

void main() {
  testWidgets('Home suggestion: loading, retry, bin change, late replies and question link', (t) async {
    t.view.physicalSize = const Size(360, 900);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = BriefRepo();
    final feed = StreamController<BinSnapshot>();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo), binProvider.overrideWith((ref) => feed.stream)]);
    addTearDown(c.dispose);
    addTearDown(feed.close);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Consumer(
                builder: (_, ref, _) {
                  final s = ref.watch(binProvider).valueOrNull;
                  return s == null ? const SizedBox() : TruncSuggestion(snapshot: s);
                },
              ),
            ),
          ),
        ),
      ),
    );
    feed.add(wet);
    await t.pump();
    await t.pump();
    expect(find.text('Checking your bin’s context…'), findsOneWidget);
    expect(find.textContaining('cardboard'), findsOneWidget);
    expect(repo.calls.single, (truncOverviewQuestion, false, 0));
    repo.pending.first.completeError(Exception('offline'));
    await t.pumpAndSettle();
    expect(find.text('Retry suggestion'), findsOneWidget);
    await t.ensureVisible(find.text('Retry suggestion'));
    await t.tap(find.text('Retry suggestion'));
    await t.pump();
    feed.add(dry);
    await t.pump();
    await t.pump();
    // The old wet response must not overwrite the new water-only decision.
    repo.pending[1].complete(answer(BinNeed.browns, 'OLD WET ANSWER'));
    repo.pending.last.complete(answer(BinNeed.water, 'Fresh dry-bin explanation.'));
    await t.pumpAndSettle();
    expect(find.text('OLD WET ANSWER'), findsNothing);
    expect(find.text('Fresh dry-bin explanation.'), findsOneWidget);
    // A normal refresh cannot display an old response when its need disagrees.
    c.invalidate(truncBriefProvider);
    c.read(truncBriefProvider);
    await t.pump();
    repo.pending.last.complete(answer(BinNeed.browns, 'WRONG NEED'));
    await t.pumpAndSettle();
    expect(find.text('WRONG NEED'), findsNothing);
    expect(find.textContaining('No food needed right now'), findsOneWidget);
    await t.ensureVisible(find.text('Ask Trunc a specific question'));
    await t.tap(find.text('Ask Trunc a specific question'));
    await t.pumpAndSettle();
    expect(find.byType(TruncScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });

  test('stale readings do not trigger Gemini or pretend to be healthy', () async {
    final stale = caseSnapshot({'top': 52, 'bottom': 48, 'greens': 3, 'browns': 7, 'stale': true});
    final repo = BriefRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo), binProvider.overrideWith((ref) => Stream.value(stale))]);
    addTearDown(c.dispose);
    final sub = c.listen(truncBriefProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(binProvider.future);
    await c.pump();
    expect(await c.read(truncBriefProvider.future), isNull);
    expect(repo.calls, isEmpty);
    expect(guidanceFor(stale).status, 'unknown');
  });
}
