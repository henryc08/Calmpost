import 'package:calmpost/data/calmpost_repository.dart';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/drop/drop_sheet.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mock bin, but the camera sees exactly [seen] (or nothing at all).
class _Repo extends MockRepository {
  _Repo(this.seen, {this.window = const Duration(seconds: 60)}) : super(Scenario.healthy);
  final List<DropGuess>? seen;
  final Duration window;
  int dismissed = 0;
  List<DropConfirmation>? confirmed;

  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);

  @override
  Future<DropSession> startDropSession() async => DropSession(id: 's1', expiresAt: DateTime.now().add(window));

  @override
  Stream<List<CameraDrop>> watchDrops() async* {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (seen == null) {
      yield const [];
      return;
    }
    yield [
      CameraDrop(id: 7, binId: 'bin-001', sessionId: 's1', time: DateTime.now(), status: DropStatus.pending, guesses: seen!, geminiOk: true, latencyMs: 1200),
    ];
  }

  @override
  Future<DropResult> confirmDrop(int dropId, List<DropConfirmation> items) async {
    confirmed = items;
    return DropResult(
      dropId: dropId,
      corrected: false,
      verdicts: [for (final i in items) if (!i.removed) await checkItem(foodById[i.catalogId]!)],
      xpAwarded: 0,
    );
  }

  @override
  Future<void> dismissDrop(int dropId) async => dismissed++;
}

DropGuess _guess(String id, {double confidence = 0.9}) =>
    DropGuess(label: foodById[id]!.name, catalogId: id, confidence: confidence, item: foodById[id], category: foodById[id]!.category, amount: 'handful', box: const [400, 300, 600, 700]);

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

/// Opens the sheet at 360dp with 1.3x text and waits for the detection.
Future<ProviderContainer> _open(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final c = ProviderContainer(overrides: [repositoryProvider.overrideWith((ref) => repo as CalmpostRepository)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => Center(child: TextButton(onPressed: () => showDropIn(context), child: const Text('open'))))),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Watching the bin…'), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 1)); // let the sheet finish resizing
  return c;
}

/// Taps a control the way a person would: scrolled into view, sheet at rest.
Future<void> _tap(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(f);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // The game shows an "Achievement unlocked" toast 2.6 s after a log.
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('detect, submit: logged as a camera drop with 0 XP', (tester) async {
    final repo = _Repo([_guess('banana_peel', confidence: 0.82)]);
    final c = await _open(tester, repo);
    expect(find.text('Something was added'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    final xp = c.read(gameProvider).totalXp;
    await _tap(tester, 'Submit');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Banana peel, logged'), findsOneWidget);
    expect(repo.confirmed!.single.catalogId, 'banana_peel');
    final log = c.read(gameProvider).logs.first;
    expect((log.item.id, log.source, log.added), ('banana_peel', LogSource.camera, true));
    expect(c.read(gameProvider).totalXp, xp, reason: 'adding a scrap earns nothing on its own');
    expect(tester.takeException(), isNull);
    await _finish(tester);
  });

  testWidgets('an unknown item must be named before submitting', (tester) async {
    final repo = _Repo([const DropGuess(label: 'something leafy', catalogId: 'unknown', confidence: 0.41)]);
    final c = await _open(tester, repo);
    expect(find.text('Check this'), findsOneWidget);
    await _tap(tester, 'something leafy');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField), 'lettuce');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Lettuce leaves').last);
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, 'Submit');
    await tester.pump(const Duration(seconds: 1));
    expect(repo.confirmed!.single.catalogId, 'lettuce');
    expect(c.read(gameProvider).logs.first.item.id, 'lettuce');
    await _finish(tester);
  });

  testWidgets('keep-out item taken back out: sent as removed, kept out, +5', (tester) async {
    final repo = _Repo([_guess('cheese')]);
    final c = await _open(tester, repo);
    expect(find.textContaining('Did you take it back out?'), findsOneWidget);
    final xp = c.read(gameProvider).totalXp;
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 300));
    await _tap(tester, 'Submit');
    await tester.pump(const Duration(seconds: 1));
    expect(repo.confirmed!.single.removed, isTrue);
    expect(find.text('${foodById['cheese']!.name}, kept out'), findsOneWidget);
    final log = c.read(gameProvider).logs.first;
    expect((log.item.id, log.added, log.source), ('cheese', false, LogSource.camera));
    expect(c.read(gameProvider).totalXp, xp + 5);
    await _finish(tester);
  });

  testWidgets('nothing was added: tells the backend and logs nothing', (tester) async {
    final repo = _Repo([_guess('banana_peel')]);
    final c = await _open(tester, repo);
    final before = c.read(gameProvider).logs.length;
    await _tap(tester, 'Nothing was added');
    await tester.pumpAndSettle(); // the sheet's closing animation starts on the next frame
    expect(find.text('Something was added'), findsNothing);
    expect(repo.dismissed, 1);
    expect(c.read(gameProvider).logs.length, before);
    await _finish(tester);
  });

  testWidgets('no motion before the window ends: "Didn\'t see anything" with a retry', (tester) async {
    // Session expiry uses the real clock, which a widget test doesn't advance,
    // so start with a window that has already run out.
    final repo = _Repo(null, window: Duration.zero);
    await _open(tester, repo);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Didn\'t see anything'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await _finish(tester);
  });
}
