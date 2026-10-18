import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:calmpost/data/social_repository.dart';
import 'package:calmpost/data/toronto_repository.dart';
import 'package:calmpost/domain/toronto.dart';
import 'package:calmpost/features/toronto/toronto_screen.dart';
import 'package:calmpost/features/toronto/toronto_learning.dart';
import 'package:calmpost/features/log/log_screen.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/providers.dart';
import 'bottom_probe_ui_test.dart' show BottomRepo;
import 'package:calmpost/state/social.dart';
import 'package:calmpost/state/toronto.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _GuestStore implements SessionStore {
  @override
  Future<SocialSession?> read() async => null;
  @override
  Future<void> write(SocialSession? session) async {}
}

Future<void> tapText(WidgetTester t, String text) async {
  final target = find.text(text).last;
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> savePreview(
  WidgetTester t,
  GlobalKey boundary,
  String name,
) async {
  expect(t.takeException(), isNull);
  if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('../artifacts/toronto')..createSync(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  late SharedPreferences prefs;
  final testData = TorontoData.fromJson(
    jsonDecode(File('assets/data/toronto_waste.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
    for (final entry
        in jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts']) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  Future<ProviderContainer> mount(
    WidgetTester t,
    Widget screen, {
    GlobalKey? boundary,
  }) async {
    final container = ProviderContainer(
      overrides: [
        gameStorageProvider.overrideWithValue(prefs),
        sessionStoreProvider.overrideWithValue(_GuestStore()),
        repositoryProvider.overrideWithValue(BottomRepo()),
        torontoDataProvider.overrideWith((ref) async => testData),
      ],
    );
    addTearDown(container.dispose);
    await container.read(socialSessionProvider.future);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            home: screen,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return container;
  }

  testWidgets(
    'Log opens Toronto and saves a city action without touching compost rewards',
    (t) async {
      final c = await mount(t, const Scaffold(body: LogScreen()));
      final before = c.read(gameProvider);
      await tapText(t, 'Toronto Challenge');
      expect(find.text('ABOUT 40%'), findsOneWidget);
      await tapText(t, 'Check a Toronto item');
      await t.enterText(find.byType(TextField), 'cheese rind');
      await t.pumpAndSettle();
      await tapText(t, 'Cheese & dairy');
      expect(find.text('Green Bin'), findsWidgets);
      expect(
        find.textContaining('Keep dairy out of your small compost bin'),
        findsOneWidget,
      );
      await tapText(t, 'I used this disposal route');
      expect(find.text('Sorting action saved'), findsOneWidget);
      expect(c.read(torontoProgressProvider).requireValue.applied, {'A1334'});
      expect(c.read(gameProvider).totalXp, before.totalXp);
      expect(c.read(gameProvider).kgDiverted, before.kgDiverted);
      expect(c.read(gameProvider).logs.length, before.logs.length);
      await tapText(t, 'Check my compost bin');
      expect(find.text('YOUR CALMPOST COMPOST BIN'), findsOneWidget);
      expect(find.text('KEEP IT OUT'), findsOneWidget);
      expect(find.text('TORONTO DISPOSAL'), findsOneWidget);
      expect(c.read(gameProvider).totalXp, before.totalXp);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    },
  );
  testWidgets(
    'all learning steps save, resume and preserve first-attempt scores',
    (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(t.view.reset);
      final boundary = GlobalKey();
      final c = await mount(
        t,
        const TorontoLearningScreen(),
        boundary: boundary,
      );
      for (final answer in ['Garbage', 'Garbage', 'Recycling']) {
        await tapText(t, answer);
        await tapText(t, 'Save answer & continue');
      }
      expect(find.text('Same scrap. Different system.'), findsOneWidget);
      await savePreview(t, boundary, '05-learning');
      for (var i = 0; i < 3; i++) {
        await tapText(t, 'I’ve explored this lesson');
      }
      for (final answer in ['Green Bin', 'Garbage', 'Recycling']) {
        await tapText(t, answer);
        await tapText(t, 'Save answer & continue');
      }
      expect(find.text('Toronto sorter'), findsOneWidget);
      await savePreview(t, boundary, '06-learning-badge');
      final p = c.read(torontoProgressProvider).requireValue;
      expect(p.complete, true);
      final data = testData;
      expect(data.score(p.before, torontoBefore), 2);
      expect(data.score(p.after, torontoAfter), 3);
      expect(TorontoProgressStore(prefs, 'guest').read().complete, true);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await mount(t, const TorontoLearningScreen());
      expect(find.text('Toronto sorter'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown material stays unknown and civic request can be copied',
    (t) async {
      final c = await mount(t, const TorontoScreen());
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      // BrandPage is lazy: scroll before looking up distant civic actions.
      await t.drag(find.byType(Scrollable).first, const Offset(0, -1600));
      await t.pumpAndSettle();
      await tapText(t, 'Copy a building request');
      expect(copied, contains('where our building collects food scraps'));
      expect(copied, contains('https://www.toronto.ca/'));
      expect(c.read(torontoProgressProvider).requireValue.applied, isEmpty);
      await t.drag(find.byType(Scrollable).first, const Offset(0, 4000));
      await t.pumpAndSettle();
      await tapText(t, 'Check a Toronto item');
      await t.enterText(find.byType(TextField), 'battery');
      await t.pumpAndSettle();
      expect(find.text('Outside our reviewed subset'), findsOneWidget);
      expect(find.textContaining('No confirmed match'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Toronto screens fit small and large-text phones and render previews',
    (t) async {
      t.view.physicalSize = const Size(824, 1830);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final boundary = GlobalKey();
      await mount(t, const TorontoScreen(), boundary: boundary);
      Future<void> capture(String name) => savePreview(t, boundary, name);
      await capture('01-toronto-challenge');
      await t.drag(find.byType(Scrollable).first, const Offset(0, -650));
      await t.pumpAndSettle();
      await capture('02-city-data');
      await t.drag(find.byType(Scrollable).first, const Offset(0, 4000));
      await t.pumpAndSettle();
      await tapText(t, 'Check a Toronto item');
      await t.enterText(find.byType(TextField), 'bones');
      await t.pumpAndSettle();
      await tapText(t, 'Chicken & meat bones');
      await capture('03-toronto-route');
      t.view.physicalSize = const Size(720, 1480);
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      await t.pumpAndSettle();
      await capture('04-small-large-text');
      for (var i = 0; i < 5; i++) {
        await t.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -350),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    },
  );
}
