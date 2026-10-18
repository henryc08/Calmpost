import 'package:calmpost/features/tutorial/tutorial_screen.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// The art loops forever, so pump fixed frames instead of pumpAndSettle.
Future<void> _settle(WidgetTester tester, [int ms = 800]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<SharedPreferences> _pumpGate(WidgetTester tester, {Map<String, Object> prefs = const {}, double textScale = 1}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [gameStorageProvider.overrideWithValue(storage)],
      child: MaterialApp(
        theme: buildTheme(),
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
        home: const TutorialGate(child: Text('HOME')),
      ),
    ),
  );
  await _settle(tester);
  return storage;
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('first launch shows the guide; Skip goes home and remembers it', (tester) async {
    final storage = await _pumpGate(tester);
    expect(find.text('What is composting?'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    await tester.tap(find.text('Skip'));
    await _settle(tester);
    expect(find.text('HOME'), findsOneWidget);
    expect(storage.getBool('tutorial_seen_v1'), isTrue);
  });

  testWidgets('Next walks all five pages, then Start composting finishes', (tester) async {
    await _pumpGate(tester);
    for (final title in ['Greens and browns', 'Microbes do the work', 'Why it matters', 'Calmpost has your back']) {
      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Next'), findsNothing);
    await tester.tap(find.text('Start composting'));
    await _settle(tester);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a returning user goes straight home', (tester) async {
    await _pumpGate(tester, prefs: {'tutorial_seen_v1': true});
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('no overflows at 360dp with large text', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pumpGate(tester, textScale: 1.3);
    for (var i = 0; i < 4; i++) {
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Next'));
      await _settle(tester);
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Start composting'), findsOneWidget);
  });
}
