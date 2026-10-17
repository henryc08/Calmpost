import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/features/drop/drop_sheet.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/data/social_repository.dart';
import 'package:calmpost/domain/inventory.dart';
import 'package:calmpost/features/inventory/inventory_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/social.dart';
import 'package:calmpost/ui/piece_counter.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements SessionStore {
  _Store([this.session]);
  final SocialSession? session;
  @override
  Future<SocialSession?> read() async => session;
  @override
  Future<void> write(SocialSession? value) async {}
}

class _Repo extends MockRepository {
  _Repo() : super(Scenario.healthy);
  bool fail = false, empty = false;
  final periods = <String>[];
  @override
  Future<CompostInventory> inventory({String period = 'all'}) async {
    periods.add(period);
    if (fail) {
      throw StateError('offline');
    }
    if (empty) {
      return const CompostInventory();
    }
    return CompostInventory(
      totalXp: 45,
      volumeXp: 10,
      careXp: 35,
      items: [
        InventoryItem(
          key: 'banana_peel',
          label: 'Banana peel',
          category: 'green',
          grams: 120,
          pieces: 2,
          entries: 2,
          uncountedEntries: 0,
          visionEntries: 2,
          lastAddedAt: DateTime(2026, 10, 17),
        ),
        InventoryItem(
          key: 'apple_core',
          label: 'Apple core',
          category: 'green',
          grams: 80,
          pieces: 2,
          entries: 1,
          uncountedEntries: 0,
          visionEntries: 1,
          lastAddedAt: DateTime(2026, 10, 17),
        ),
        InventoryItem(
          key: 'cardboard',
          label: 'Shredded cardboard',
          category: 'brown',
          grams: 400,
          pieces: 1,
          entries: 3,
          uncountedEntries: 2,
          visionEntries: 0,
          lastAddedAt: DateTime(2026, 10, 16),
        ),
      ],
    );
  }
}

Future<void> fonts() async {
  final icons = FontLoader('packages/phosphor_flutter/PhosphorRegular');
  icons.addFont(rootBundle.load('packages/phosphor_flutter/lib/fonts/Phosphor.ttf'));
  await icons.load();
  for (final entry in {
    'Manrope': ['500', '600', '700', '800'],
    'Fraunces': ['400', '500'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final w in entry.value) {
      loader.addFont(rootBundle.load('assets/fonts/${entry.key}-$w.ttf'));
    }
    await loader.load();
  }
}

Future<void> capture(GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('INVENTORY_SCREENSHOTS')) {
    return;
  }
  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('/tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}

void main() {
  setUpAll(fonts);
  for (final width in [360.0, 412.0]) {
    testWidgets('inventory ${width}dp large text: totals, score, search and filters', (t) async {
      t.view.physicalSize = Size(width, 820);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = _Repo();
      final key = GlobalKey();
      await t.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo), sessionStoreProvider.overrideWithValue(_Store())],
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: RepaintBoundary(key: key, child: const InventoryScreen()),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('600 g'), findsOneWidget);
      expect(find.text('5 counted pieces / portions · 6 additions'), findsOneWidget);
      await t.runAsync(() => capture(key, 'calmpost-inventory-${width.toInt()}-summary'));
      await t.ensureVisible(find.text('2 × Banana peel'));
      await t.pumpAndSettle();
      await t.runAsync(() => capture(key, 'calmpost-inventory-${width.toInt()}-items'));
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('COMPOST SCORE'));
      await t.pumpAndSettle();
      expect(find.text('45 XP'), findsOneWidget);
      await t.ensureVisible(find.byType(TextField));
      await t.enterText(find.byType(TextField), 'apple');
      await t.pump();
      expect(find.text('2 × Apple core'), findsOneWidget);
      expect(find.text('2 × Banana peel'), findsNothing);
      await t.ensureVisible(find.text('This week'));
      await t.pumpAndSettle();
      await t.tap(find.text('This week'));
      await t.pumpAndSettle();
      expect(repo.periods, contains('week'));
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'apple');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 21));
    });
  }
  testWidgets('failed load, retry and empty inventory', (t) async {
    final repo = _Repo()..fail = true;
    await t.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo), sessionStoreProvider.overrideWithValue(_Store())],
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: InventoryScreen()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Could not load your compost. Try refreshing.'), findsOneWidget);
    repo
      ..fail = false
      ..empty = true;
    await t.ensureVisible(find.text('Refresh'));
    await t.tap(find.text('Refresh'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.textContaining('Nothing confirmed yet.'));
    await t.pumpAndSettle();
    expect(find.textContaining('Nothing confirmed yet.'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 21));
  });
  testWidgets('signed-in owner can resume and review a camera detection', (t) async {
    const session = SocialSession(server: 'http://localhost:8000', token: 'owner-token', userId: 'player_1', binId: 'bin-001');
    var fetched = false;
    final repo = ApiRepository(
      const ApiConfig(baseUrl: 'http://localhost:8000', apiKey: '', token: 'owner-token'),
      client: MockClient((r) async {
        expect(r.url.path, '/bins/bin-001/drops/pending');
        expect(r.headers['Authorization'], 'Bearer owner-token');
        fetched = true;
        return http.Response(
          jsonEncode([
            {
              'id': 7,
              'items': [
                {'catalog_id': 'banana_peel', 'label': 'Banana peel', 'category': 'green', 'amount': 'handful', 'piece_count': 2, 'est_grams': 100, 'confidence': .9},
              ],
            },
          ]),
          200,
        );
      }),
    );
    addTearDown(repo.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo), sessionStoreProvider.overrideWithValue(_Store(session)), dataSourceProvider.overrideWith((_) => DataSource.live)],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(onPressed: () => showDropSheet(context), child: const Text('Open camera')),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Open camera'));
    await t.pumpAndSettle();
    expect(fetched, isTrue);
    expect(find.text('Is this right?'), findsOneWidget);
    expect(find.textContaining('2 × · Green'), findsOneWidget);
    expect(find.text('Connect your bin first'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
  testWidgets('piece count and validated total weight editor', (t) async {
    var count = 1;
    double? grams;
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                PieceCounter(value: count, onChanged: (v) => setState(() => count = v)),
                TextButton(
                  onPressed: () async {
                    grams = await editCompostWeight(context, 90);
                  },
                  child: const Text('Weight'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byTooltip('More pieces'));
    await t.pump();
    expect(count, 2);
    await t.tap(find.text('Weight'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '0');
    await t.pump();
    expect(find.text('Enter 1–5000 g'), findsOneWidget);
    await t.enterText(find.byType(TextField), '85');
    await t.pump();
    await t.tap(find.text('Use weight'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 1));
    expect(grams, 85);
    expect(t.takeException(), isNull);
  });
}
