// Camera drop-in data layer (AGENTS.md 2.4). No UI here: these cover the
// contract a sheet is built against, so the shapes are pinned before anyone
// draws them. Payloads are copied from drops.py `_public()` and
// `ConfirmResponse`, not invented.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';

const _config = ApiConfig(baseUrl: 'http://10.0.0.5:8000', apiKey: 'k', binId: 'bin-001');

/// A one-pixel JPEG is enough to prove the base64 round-trips.
final _jpegBytes = [0xFF, 0xD8, 0xFF, 0xD9];

Map<String, dynamic> _dropJson({
  int id = 7,
  String status = 'pending',
  bool geminiOk = true,
  List<Map<String, dynamic>>? items,
  String? thumb,
}) => {
  'id': id,
  'bin_id': 'bin-001',
  'session_id': 'abc123',
  'time': '2026-10-17T18:04:00+00:00',
  'status': status,
  'items': items ??
      [
        {
          'label': 'banana peel',
          'catalog_id': 'banana_peel',
          'category': 'green',
          'est_grams': 110.0,
          'amount': 'handful',
          'confidence': 0.95,
          'box_2d': [120, 240, 700, 760],
        },
      ],
  'gemini_ok': geminiOk,
  'model': 'gemini-2.5-flash',
  'error': null,
  'latency_ms': 1420,
  'thumbnail_jpeg_b64': thumb ?? base64Encode(_jpegBytes),
};

ApiRepository _repo(Future<http.Response> Function(http.Request) handler) =>
    ApiRepository(_config, client: MockClient(handler), dropPollEvery: const Duration(milliseconds: 10));

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

void main() {
  group('dropFromJson', () {
    test('parses a pending detection the way the backend sends it', () {
      final drop = dropFromJson(_dropJson());

      expect(drop.id, 7);
      expect(drop.sessionId, 'abc123');
      expect(drop.status, DropStatus.pending);
      expect(drop.geminiOk, isTrue);
      expect(drop.latencyMs, 1420);
      expect(drop.time.isUtc, isFalse, reason: 'times are converted to local for display');
      expect(drop.thumbnailJpeg, _jpegBytes);

      final guess = drop.guesses.single;
      expect(guess.label, 'banana peel');
      expect(guess.confidence, 0.95);
      expect(guess.category, FoodCategory.green);
      expect(guess.amount, 'handful');
      expect(guess.estGrams, 110.0);
      // [ymin, xmin, ymax, xmax] on 0-1000, straight through.
      expect(guess.box, [120, 240, 700, 760]);
      expect(guess.item?.id, 'banana_peel');
    });

    test('an unknown catalog_id leaves item null for the user to name', () {
      final drop = dropFromJson(_dropJson(items: [
        {'label': 'mystery goo', 'catalog_id': 'unknown', 'category': null, 'confidence': 0.3},
      ]));

      final guess = drop.guesses.single;
      expect(guess.item, isNull);
      expect(guess.category, isNull, reason: 'the backend could not categorise it');
      expect(guess.box, isNull);
      expect(guess.amount, isNull);
    });

    test('no thumbnail is null rather than empty bytes', () {
      expect(dropFromJson(_dropJson(thumb: '')).thumbnailJpeg, isNull);
    });

    test('a rules-fallback detection is flagged so the UI can say so', () {
      // What a Gemini 429 produces: the drop still arrives, cruder.
      final drop = dropFromJson({..._dropJson(geminiOk: false), 'model': 'rules-fallback'});
      expect(drop.geminiOk, isFalse);
      expect(drop.model, 'rules-fallback');
    });

    test('an empty item list is a drop with nothing named, not an error', () {
      expect(dropFromJson(_dropJson(items: [])).guesses, isEmpty);
    });
  });

  group('foodForLabel', () {
    test('prefers the catalog id over the label', () {
      expect(foodForLabel('whatever the model said', 'banana_peel')?.id, 'banana_peel');
    });

    test('falls back to matching the label', () {
      expect(foodForLabel('coffee grounds')?.id, 'coffee_grounds');
    });

    test('is null for an item the catalog has never heard of', () {
      expect(foodForLabel('plutonium', 'unknown'), isNull);
      expect(foodForLabel(''), isNull);
    });
  });

  group('ApiRepository', () {
    test('startDropSession arms the camera and reads the deadline', () async {
      late http.Request seen;
      final repo = _repo((req) async {
        seen = req;
        return _json({'session_id': 'f00d', 'expires_at': '2026-10-17T18:05:00+00:00'}, 201);
      });

      final session = await repo.startDropSession();

      expect(seen.method, 'POST');
      expect(seen.url.path, '/bins/bin-001/drops/session');
      expect(session.id, 'f00d');
      expect(session.expiresAt.isUtc, isFalse);
    });

    test('watchDrops polls and keeps going after a failed tick', () async {
      var calls = 0;
      final repo = _repo((req) async {
        calls++;
        if (calls == 2) return http.Response('boom', 500);
        return _json([_dropJson(id: calls)]);
      });

      final seen = await repo.watchDrops().take(3).toList();

      // The failed tick yields nothing but must not end the stream, so the
      // three emissions come from calls 1, 3 and 4.
      expect(seen.map((l) => l.single.id), [1, 3, 4]);
    });

    test('confirmDrop sends what the user settled on and sums the XP', () async {
      late Map<String, dynamic> body;
      final repo = _repo((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'drop_id': 7,
          'status': 'confirmed',
          'corrected': true,
          'items': [
            {
              'log': {'item': 'banana peel', 'catalog_id': 'banana_peel', 'xp_awarded': 15},
              'verdict': {'verdict': 'great', 'headline': 'Good add', 'reason': 'balances the browns', 'pair_with': []},
            },
            {
              // A removed keep-out item: logged, no verdict.
              'log': {'item': 'cheese rind', 'catalog_id': 'cheese', 'xp_awarded': 5},
              'verdict': null,
            },
          ],
        });
      });

      final result = await repo.confirmDrop(7, const [
        DropConfirmation(label: 'banana peel', catalogId: 'banana_peel', category: FoodCategory.green, amount: 'handful', wasAdvised: true),
        DropConfirmation(label: 'cheese rind', catalogId: 'cheese', removed: true),
      ]);

      final sent = (body['items'] as List).cast<Map<String, dynamic>>();
      expect(sent.first['label'], 'banana peel');
      expect(sent.first['category'], 'green');
      expect(sent.first['amount'], 'handful');
      expect(sent.first['was_advised'], isTrue);
      expect(sent.last['removed'], isTrue);
      // Never guessed at: the backend decides the category by its own rules.
      expect(sent.last['category'], 'unknown');

      expect(result.corrected, isTrue);
      expect(result.xpAwarded, 20);
      expect(result.verdicts.single.verdict, Verdict.great);
      expect(result.verdicts.single.item.id, 'banana_peel');
    });

    test('an already-handled drop surfaces the conflict rather than silently passing', () async {
      final repo = _repo((req) async => _json({'detail': 'drop was already handled'}, 409));
      await expectLater(
        repo.confirmDrop(7, const [DropConfirmation(label: 'banana peel', catalogId: 'banana_peel')]),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)),
      );
    });

    test('dismissDrop posts to the dismiss route', () async {
      late http.Request seen;
      final repo = _repo((req) async {
        seen = req;
        return _json({'drop_id': 7, 'status': 'dismissed'});
      });

      await repo.dismissDrop(7);

      expect(seen.method, 'POST');
      expect(seen.url.path, '/drops/7/dismiss');
    });
  });

  _photoTests();

  group('MockRepository', () {
    test('arming produces a pending drop, and confirming clears it', () async {
      final repo = MockRepository(Scenario.healthy);

      final session = await repo.startDropSession();
      expect(session.open, isTrue);
      expect(session.remaining.inSeconds, greaterThan(50));

      final drop = await repo.watchDrops().firstWhere((l) => l.isNotEmpty).then((l) => l.single);
      expect(drop.guesses.single.item?.id, 'banana_peel');

      final result = await repo.confirmDrop(drop.id, [
        DropConfirmation(label: drop.guesses.single.label, catalogId: 'banana_peel', category: FoodCategory.green),
      ]);
      expect(result.corrected, isFalse, reason: 'the user accepted the guess');
      expect(result.verdicts, hasLength(1));

      expect(await repo.watchDrops().first, isEmpty);
    });

    test('dismissing clears it without logging anything', () async {
      final repo = MockRepository(Scenario.healthy);
      await repo.startDropSession();
      final drop = await repo.watchDrops().firstWhere((l) => l.isNotEmpty).then((l) => l.single);

      await repo.dismissDrop(drop.id);

      expect(await repo.watchDrops().first, isEmpty);
    });

    test('each arm serves the next scripted case, including an unknown item', () async {
      final repo = MockRepository(Scenario.healthy);
      final labels = <List<String>>[];

      for (var i = 0; i < 4; i++) {
        await repo.startDropSession();
        final drop = await repo.watchDrops().firstWhere((l) => l.isNotEmpty).then((l) => l.last);
        labels.add(drop.guesses.map((g) => g.label).toList());
        await repo.dismissDrop(drop.id);
      }

      expect(labels[0], ['banana peel']);
      expect(labels[1], ['coffee grounds', 'eggshells'], reason: 'a sheet has to handle more than one item');
      expect(labels[2], ['something leafy']);
      expect(labels[3], ['cheese rind']);
    });

    test('correcting the guess is reported as corrected', () async {
      final repo = MockRepository(Scenario.healthy);
      await repo.startDropSession();
      final drop = await repo.watchDrops().firstWhere((l) => l.isNotEmpty).then((l) => l.single);

      final result = await repo.confirmDrop(drop.id, const [
        DropConfirmation(label: 'apple core', catalogId: 'apple_core', category: FoodCategory.green),
      ]);

      expect(result.corrected, isTrue);
    });
  });
}

// --- single photo submission -------------------------------------------------
//
// The camera decides for itself that something arrived; this is the user
// pointing a phone at something. It comes back as an ordinary pending drop, so
// confirmDrop and dismissDrop finish it the same way.

void _photoTests() {
  group('ApiRepository.submitPhoto', () {
    test('posts the image and parses the drop it becomes', () async {
      late http.Request seen;
      final repo = _repo((req) async {
        seen = req;
        return _json({..._dropJson(id: 11), 'source': 'photo'}, 201);
      });

      final drop = await repo.submitPhoto(Uint8List.fromList(_jpegBytes));

      expect(seen.method, 'POST');
      expect(seen.url.path, '/bins/bin-001/drops/photo');
      expect(base64Decode((jsonDecode(seen.body) as Map)['image_jpeg_b64'] as String), _jpegBytes);

      expect(drop.id, 11);
      expect(drop.source, 'photo');
      expect(drop.fromPhoto, isTrue);
      expect(drop.status, DropStatus.pending);
      expect(drop.guesses.single.item?.id, 'banana_peel');
    });

    test('a camera drop is not flagged as a photo', () {
      // No source in the payload means camera: older rows predate the column.
      expect(dropFromJson(_dropJson()).fromPhoto, isFalse);
      expect(dropFromJson(_dropJson()).source, 'camera');
    });

    test('a failed identification is a drop with nothing named, not an error', () async {
      final repo = _repo((req) async => _json({
        ..._dropJson(id: 12, items: [], geminiOk: false),
        'source': 'photo',
        'error': '429 quota exhausted',
      }, 201));

      final drop = await repo.submitPhoto(Uint8List.fromList(_jpegBytes));

      expect(drop.guesses, isEmpty, reason: 'the user names it by hand');
      expect(drop.geminiOk, isFalse);
      expect(drop.error, '429 quota exhausted');
      expect(drop.thumbnailJpeg, isNotNull, reason: 'the photo is kept');
    });

    test('an oversized image surfaces the 413 rather than failing quietly', () async {
      final repo = _repo((req) async => _json({'detail': 'image is too big; downscale'}, 413));
      await expectLater(
        repo.submitPhoto(Uint8List.fromList(_jpegBytes)),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 413)),
      );
    });
  });

  group('MockRepository.submitPhoto', () {
    test('identifies a photo and leaves it pending for confirmation', () async {
      final repo = MockRepository(Scenario.healthy);

      final drop = await repo.submitPhoto(Uint8List.fromList(_jpegBytes));

      expect(drop.fromPhoto, isTrue);
      expect(drop.status, DropStatus.pending);
      expect(drop.guesses.single.label, 'banana peel');
      expect(drop.guesses.single.box, hasLength(4), reason: 'a box to draw');

      // Appears in the same watch the camera drops use.
      expect((await repo.watchDrops().first).single.id, drop.id);

      // And finishes through the shared path.
      await repo.confirmDrop(drop.id, const [
        DropConfirmation(label: 'banana peel', catalogId: 'banana_peel', category: FoodCategory.green),
      ]);
      expect(await repo.watchDrops().first, isEmpty);
    });

    test('an empty image stands in for a failed identification', () async {
      final drop = await MockRepository(Scenario.healthy).submitPhoto(Uint8List(0));

      expect(drop.guesses, isEmpty);
      expect(drop.geminiOk, isFalse);
      expect(drop.status, DropStatus.pending, reason: 'still answerable by hand');
    });
  });
}
