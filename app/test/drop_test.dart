import 'dart:convert';

import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/domain/drop.dart';
import 'package:calmpost/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Detection det(String label, String? id, double conf) => Detection(label: label, catalogId: id, confidence: conf, category: foodById[id]?.category);

void main() {
  group('tiers: how hard the pop-up asks', () {
    test('every item matched and sure: confident (still asked "Is this right?")', () {
      expect(tierOf(Drop(id: 1, items: [det('banana peel', 'banana_peel', 0.9)]), foodById), DropTier.confident);
    });

    test('a low-confidence or unmatched item: check', () {
      expect(tierOf(Drop(id: 1, items: [det('banana peel', 'banana_peel', 0.9), det('paper?', 'newspaper', 0.45)]), foodById), DropTier.check);
      expect(tierOf(Drop(id: 1, items: [det('banana peel', 'banana_peel', 0.9), det('dragonfruit', null, 0.8)]), foodById), DropTier.check);
    });

    test('nothing usable, Gemini failed, or a mix it could not separate: unclear', () {
      expect(tierOf(const Drop(id: 1, items: []), foodById), DropTier.unclear);
      expect(tierOf(Drop(id: 1, items: [det('banana peel', 'banana_peel', 0.9)], geminiOk: false), foodById), DropTier.unclear);
      expect(tierOf(Drop(id: 1, items: [det('blob', null, 0.3)]), foodById), DropTier.unclear);
      expect(tierOf(Drop(id: 1, items: [det('mixed scraps: rice, peels', mixedScrapsId, 0.4)]), foodById), DropTier.unclear);
    });
  });

  test('rows: catalog items take the catalog (rules); unknown ones keep the label for the user to fix', () {
    final lines = linesFor(Drop(id: 1, items: [det('banana peel', 'banana_peel', 0.9), det('dragonfruit skin', null, 0.7)]), foodById);
    expect(lines[0].item, foodById['banana_peel']);
    expect(lines[0].check, isFalse);
    expect(lines[1].isCustom, isTrue);
    expect(lines[1].item.name, 'Dragonfruit skin');
    expect(lines[1].check, isTrue);
  });

  test('"Mixed food scraps" is in the catalog as a green', () {
    expect(foodById[mixedScrapsId]?.category, FoodCategory.green);
  });

  test('corrected: what the user saved differs from the first guess', () {
    final d = Drop(id: 1, items: [det('banana peel', 'banana_peel', 0.9)]);
    expect(corrected(d, linesFor(d, foodById)), isFalse);
    expect(corrected(d, [DropLine(item: foodById['coffee_grounds']!, amount: Amount.small)]), isTrue);
  });

  group('API', () {
    ApiRepository repo(Future<http.Response> Function(http.Request) h) => ApiRepository(
      const ApiConfig(baseUrl: 'http://bin.test', apiKey: 'k'),
      client: MockClient(h),
      dropPollEvery: const Duration(milliseconds: 5),
    );
    http.Response json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    final session = DropSession('s1', DateTime(2100));

    test('watchDrop polls until this session\'s drop is pending', () async {
      var polls = 0;
      final r = repo((req) async {
        if (req.url.path.endsWith('/drops/pending')) {
          polls++;
          return json(
            polls < 3
                ? []
                : [
                    {'id': 9, 'session_id': 'other', 'items': []},
                    {
                      'id': 7,
                      'session_id': 's1',
                      'gemini_ok': true,
                      'thumbnail_jpeg_b64': base64Encode([1, 2, 3]),
                      'items': [
                        {'label': 'banana peel', 'catalog_id': 'banana_peel', 'category': 'green', 'amount': 'handful', 'confidence': 0.86, 'box_2d': [1, 2, 3, 4]},
                        {'label': 'mystery', 'catalog_id': 'unknown', 'confidence': 0.3},
                      ],
                    },
                  ],
          );
        }
        return json({'open': true});
      });
      final e = await r.watchDrop(session).first;
      expect(e, isA<DropSeen>());
      final d = (e as DropSeen).drop;
      expect(d.id, 7);
      expect(d.thumbnail, [1, 2, 3]);
      expect(d.items.first.amount, Amount.handful);
      expect(d.items.last.catalogId, isNull);
    });

    test('watchDrop ends with nothing when the window closes empty', () async {
      final r = repo((req) async => req.url.path.endsWith('/drops/pending') ? json([]) : json({'open': false, 'close_reason': 'no_motion'}));
      expect(await r.watchDrop(session).first, isA<DropNothing>());
    });

    test('confirmDrop sends the edited rows and maps each verdict', () async {
      late Map<String, dynamic> sent;
      final r = repo((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return json({
          'items': [
            {'log': {}, 'verdict': {'verdict': 'great', 'headline': 'Great add!', 'reason': 'Dry bin.', 'pair_with': []}},
            {'log': {}, 'verdict': null},
          ],
        });
      });
      final lines = [
        DropLine(item: foodById['mixed_scraps']!, amount: Amount.large),
        DropLine(item: foodById['meat']!, amount: Amount.small, removed: true),
      ];
      final v = await r.confirmDrop(const Drop(id: 7, items: []), lines, advisedIds: {'mixed_scraps'});
      expect(sent['items'], [
        {'label': 'Mixed food scraps', 'catalog_id': 'mixed_scraps', 'category': 'green', 'amount': 'large', 'removed': false, 'was_advised': true},
        {'label': 'Meat scraps', 'catalog_id': 'meat', 'category': 'avoid', 'amount': 'small', 'removed': true, 'was_advised': false},
      ]);
      expect(v.map((a) => a.verdict), [Verdict.great, Verdict.avoid]);

      // A custom item goes up as 'unknown' with its own label and type.
      await r.confirmDrop(const Drop(id: 7, items: []), [DropLine(item: customFood('dragonfruit skin', FoodCategory.green, Amount.small), amount: Amount.small)]);
      expect((sent['items'] as List).single, containsPair('catalog_id', 'unknown'));
      expect((sent['items'] as List).single, containsPair('label', 'Dragonfruit skin'));
    });
  });
}

