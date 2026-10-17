import 'package:calmpost/data/calmpost_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/drop/drop_sheet.dart';
import 'package:calmpost/domain/xp_rules.dart';
import 'package:calmpost/main.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock bin with one reading (no timers left behind) and a quick camera.
class _Repo extends MockRepository {
  _Repo(this.kind) : super(Scenario.tooDry) {
    nextDrop = kind;
    dropDelay = const Duration(milliseconds: 300);
  }
  final MockDrop kind;

  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
}

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

/// Small phone, large text: the pop-up must fit.
Future<ProviderContainer> _open(WidgetTester tester, MockDrop kind) async {
  tester.view.physicalSize = const Size(360 * 3, 740 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final container = ProviderContainer(overrides: [repositoryProvider.overrideWith((ref) => _Repo(kind) as CalmpostRepository)]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CalmpostApp()));
  await _settle(tester);
  await tester.tap(find.text('Drop something in'));
  await _settle(tester, 300);
  expect(find.text('Watching the bin…'), findsOneWidget);
  await _settle(tester, 1000);
  return container;
}

/// Only what's in the drop sheet (Home behind it lists some of the same items).
Finder _s(Finder f) => find.descendant(of: find.byType(DropSheet), matching: f);

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _settle(tester, 300);
  await tester.tap(f);
  await _settle(tester, 400);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('a confident detection is still asked about, and a confident mistake can be fixed', (tester) async {
    final c = await _open(tester, MockDrop.banana);
    expect(_s(find.text('Is this right?')), findsOneWidget);
    expect(_s(find.text('Banana peel')), findsOneWidget);
    expect(_s(find.textContaining('86% sure')), findsOneWidget);
    expect(_s(find.text('Yes, that\'s right')), findsOneWidget);
    expect(c.read(gameProvider).cameraDrops, 0); // nothing logged before the user answers

    // Gemini was sure, and wrong: it was coffee grounds.
    await _tapVisible(tester, _s(find.text('Banana peel')));
    await tester.enterText(_s(find.byType(TextField)), 'coffee');
    await _settle(tester, 300);
    await _tapVisible(tester, _s(find.text('Coffee grounds')));
    expect(_s(find.text('Banana peel')), findsNothing);
    expect(_s(find.text('Save')), findsOneWidget);

    await _tapVisible(tester, _s(find.text('Save')));
    await _settle(tester, 800);
    expect(_s(find.text('LOGGED')), findsOneWidget);
    expect(_s(find.textContaining('Thanks for the fix')), findsOneWidget);
    final g = c.read(gameProvider);
    expect(g.cameraDrops, 1);
    expect(g.logs.first.item.id, 'coffee_grounds');

    await _tapVisible(tester, _s(find.text('Done')));
    await _finish(tester);
  });

  testWidgets('a mix the camera can\'t separate: pick what was in it, and keep-outs get taken back out', (tester) async {
    final c = await _open(tester, MockDrop.mixed);
    expect(_s(find.text('What went in?')), findsOneWidget);
    expect(_s(find.text('Mixed food scraps')), findsWidgets); // its row, and the pre-ticked quick pick
    expect(_s(find.text('ANY OF THESE IN IT?')), findsOneWidget);

    await _tapVisible(tester, _s(find.text('Meat scraps')));
    expect(_s(find.text('Take it back out, then tick here.')), findsOneWidget);
    await _tapVisible(tester, _s(find.text('Take it back out, then tick here.')));
    expect(_s(find.text('Taken back out. Thank you.')), findsOneWidget);

    final before = c.read(gameProvider).totalXp;
    await _tapVisible(tester, _s(find.text('Save')));
    await _settle(tester, 800);
    expect(_s(find.text('KEPT OUT · Meat scraps')), findsOneWidget);
    expect(c.read(gameProvider).totalXp, before + Xp.avoidedBadAdd + 12); // 250 g mixed scraps
    expect(c.read(gameProvider).logs.map((l) => l.item.id).take(2).toSet(), {'mixed_scraps', 'meat'});
    await _finish(tester);
  });

  testWidgets('camera couldn\'t make it out: nothing pre-filled, save waits for a pick', (tester) async {
    await _open(tester, MockDrop.unclear);
    expect(_s(find.textContaining('couldn\'t make it out')), findsOneWidget);
    expect(_s(find.text('Nothing picked yet.')), findsOneWidget);
    await _tapVisible(tester, _s(find.text('Veggie peels')));
    expect(_s(find.text('Nothing picked yet.')), findsNothing);
    await _tapVisible(tester, _s(find.text('Save')));
    await _settle(tester, 800);
    expect(_s(find.text('LOGGED')), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('unsure items are marked "Check this"', (tester) async {
    await _open(tester, MockDrop.check);
    expect(_s(find.text('Check this')), findsOneWidget);
    expect(_s(find.textContaining('44% sure')), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('a false trigger: "Nothing was added" logs nothing', (tester) async {
    final c = await _open(tester, MockDrop.banana);
    await _tapVisible(tester, _s(find.text('Nothing was added')));
    await _settle(tester, 600);
    expect(_s(find.text('Is this right?')), findsNothing);
    expect(c.read(gameProvider).cameraDrops, 0);
    await _finish(tester);
  });

  testWidgets('nothing seen: offers to log it by hand', (tester) async {
    final c = await _open(tester, MockDrop.nothing);
    expect(_s(find.text('Didn\'t see anything')), findsOneWidget);
    await _tapVisible(tester, _s(find.text('Log it by hand')));
    await _settle(tester, 600);
    expect(c.read(tabProvider), AppTab.log);
    await _finish(tester);
  });
}
