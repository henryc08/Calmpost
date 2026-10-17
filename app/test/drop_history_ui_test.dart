import 'dart:convert';
import 'dart:typed_data';
import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/drop.dart';
import 'package:calmpost/domain/drop_history.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/features/history/drop_history_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final past = PastDrop(
  id: 1,
  time: DateTime(2026, 10, 17),
  status: DropStatus.confirmed,
  source: 'photo',
  guesses: ['banana peel'],
  items: const [PastDropItem(label: 'Apple core', category: 'green', grams: 40, pieces: 1)],
  corrected: true,
  hasPhoto: true,
);

class HistoryRepo extends MockRepository {
  HistoryRepo() : super(Scenario.healthy);
  bool fail = true, photoFail = true;
  final cursors = <String?>[];
  @override
  Future<DropHistoryPage> dropHistory({String? before, int limit = 20}) async {
    cursors.add(before);
    if (fail) throw Exception('network');
    return before == null ? DropHistoryPage(drops: [past], nextBefore: 'cursor') : const DropHistoryPage(drops: []);
  }

  @override
  Future<Uint8List?> dropPhoto(int id) async {
    if (photoFail) throw Exception('offline');
    return null;
  }
}

void main() {
  test('history cursor, corrections and photo authentication use the repository', () async {
    final r = ApiRepository(
      const ApiConfig(baseUrl: 'http://bin.test', apiKey: '', token: 'session'),
      client: MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer session');
        if (req.url.path.endsWith('/photo')) return http.Response('', 404);
        expect(req.url.queryParameters['before'], '2026-10-17T01:00:00.123456Z');
        return http.Response(
          jsonEncode({
            'drops': [
              {
                'id': 1,
                'time': '2026-10-17T01:00:00Z',
                'status': 'confirmed',
                'source': 'photo',
                'items': [
                  {'label': 'banana peel'},
                ],
                'final_items': [
                  {'label': 'apple core', 'category': 'green', 'removed': false, 'quantity_g': 40},
                ],
                'corrected': true,
                'has_photo': true,
              },
            ],
            'next_before': null,
          }),
          200,
        );
      }),
    );
    addTearDown(r.close);
    final page = await r.dropHistory(before: '2026-10-17T01:00:00.123456Z');
    expect(page.drops.single.guesses, ['banana peel']);
    expect(page.drops.single.items.single.label, 'apple core');
    expect(page.drops.single.corrected, true);
    expect(await r.dropPhoto(1), isNull);
  });
  test('mock reviewed photos populate history once and retain the original guess', () async {
    final r = MockRepository(Scenario.healthy);
    final raw = await r.submitPhoto(Uint8List.fromList([1, 2, 3]));
    final drop = Drop.fromCamera(raw);
    final lines = [DropLine(item: foodById['apple_core']!, amount: Amount.small)];
    await r.confirmReviewedDrop(drop, lines);
    await r.confirmReviewedDrop(drop, lines);
    final page = await r.dropHistory();
    expect(page.drops, hasLength(1));
    expect(page.drops.single.source, 'photo');
    expect(page.drops.single.guesses, ['banana peel']);
    expect(page.drops.single.corrected, true);
    expect(await r.dropPhoto(drop.id), [1, 2, 3]);
    expect((await r.inventory()).items, hasLength(1));
  });
  testWidgets('history retries, pages and distinguishes an expired photo from an error', (t) async {
    t.view.physicalSize = const Size(360, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = HistoryRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: buildTheme(), home: const DropHistoryScreen()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Retry history'), findsOneWidget);
    repo.fail = false;
    await t.tap(find.text('Retry history'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Load older drops'));
    await t.pumpAndSettle();
    await t.tap(find.text('Load older drops'));
    await t.pumpAndSettle();
    expect(repo.cursors.last, 'cursor');
    expect(find.text('Load older drops'), findsNothing);
    await t.ensureVisible(find.text('Apple core'));
    await t.pumpAndSettle();
    await t.tap(find.text('Apple core'));
    await t.pumpAndSettle();
    expect(find.text('Retry photo'), findsOneWidget);
    repo.photoFail = false;
    await t.tap(find.text('Retry photo'));
    await t.pumpAndSettle();
    expect(find.text('Photo no longer available.'), findsOneWidget);
    expect(find.text('banana peel'), findsOneWidget);
    c.updateOverrides([repositoryProvider.overrideWithValue(MockRepository(Scenario.healthy))]);
    await t.pumpAndSettle();
    expect(find.text('banana peel'), findsNothing);
    expect(find.text('Reopen history for the current bin.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
