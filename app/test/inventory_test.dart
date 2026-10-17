import 'dart:convert';
import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('review preserves count and total mass independently', () {
    final drop = reviewedDropFromJson({
      'id': 1,
      'items': [
        {'label': 'banana peel', 'catalog_id': 'banana_peel', 'piece_count': 2, 'est_grams': 90, 'amount': 'handful', 'confidence': .9},
      ],
    });
    final line = linesFor(drop, foodById).single;
    expect(line.pieceCount, 2);
    expect(line.grams, 90);
    expect(line.copyWith(pieceCount: 3).grams, 90);
    expect(line.copyWith(amount: Amount.large).grams, 250);
    expect(corrected(drop, [line.copyWith(pieceCount: 3)]), isTrue);
  });
  test('mock inventory records confirmed inputs once, excluding keep-out', () async {
    final repo = MockRepository(Scenario.tooDry);
    expect((await repo.inventory()).items, isEmpty);
    const drop = Drop(id: 4, items: []);
    final lines = [
      DropLine(item: foodById['banana_peel']!, amount: Amount.handful, pieceCount: 2, quantityG: 90),
      DropLine(item: foodById['apple_core']!, amount: Amount.small, pieceCount: 2, quantityG: 80),
      DropLine(item: foodById['cheese']!, amount: Amount.small, removed: true),
    ];
    await repo.confirmReviewedDrop(drop, lines);
    await repo.confirmReviewedDrop(drop, lines);
    for (var i = 0; i < 2; i++) {
      await repo.logItem(foodById['banana_peel']!, quantityG: 30, pieceCount: 1, requestId: 'manual-1');
    }
    final inventory = await repo.inventory();
    expect(inventory.grams, 200);
    expect(inventory.pieces, 5);
    expect(inventory.entries, 3);
    expect(inventory.items.where((i) => i.label == 'Banana peel').single.pieces, 3);
    expect(inventory.items.fold<int>(0, (sum, i) => sum + i.visionEntries), 2);
  });
  test('API sends reviewed counts and mass and reads score breakdown', () async {
    final repo = ApiRepository(
      const ApiConfig(baseUrl: 'http://localhost:8000', apiKey: '', token: 'owner-token'),
      client: MockClient((r) async {
        expect(r.headers['Authorization'], 'Bearer owner-token');
        if (r.method == 'POST') {
          expect(r.url.path, '/drops/4/confirm');
          final row = (jsonDecode(r.body)['items'] as List).single;
          expect(row['piece_count'], 2);
          expect(row['quantity_g'], 90);
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'log': {'xp_awarded': 4},
                },
              ],
            }),
            200,
          );
        }
        expect(r.url.path, '/bins/bin-001/inventory');
        expect(r.url.queryParameters['period'], 'week');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'item_key': 'banana_peel',
                'label': 'Banana peel',
                'category': 'green',
                'grams': 90,
                'pieces': 2,
                'entries': 1,
                'uncounted_entries': 0,
                'vision_entries': 1,
                'last_added_at': '2026-10-17T12:00:00Z',
              },
            ],
            'total_xp': 9,
            'volume_xp': 4,
            'care_xp': 5,
          }),
          200,
        );
      }),
    );
    addTearDown(repo.close);
    await repo.confirmReviewedDrop(const Drop(id: 4, items: []), [DropLine(item: foodById['banana_peel']!, amount: Amount.handful, pieceCount: 2, quantityG: 90)]);
    final inventory = await repo.inventory(period: 'week');
    expect(inventory.grams, 90);
    expect(inventory.pieces, 2);
    expect(inventory.totalXp, 9);
    expect(inventory.volumeXp, 4);
    expect(inventory.careXp, 5);
  });
}
