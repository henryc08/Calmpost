// Trunc's data layer. No UI here: these pin the contract a chat screen is
// built against. Payloads are copied from the backend's ChatReply model.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';

const _config = ApiConfig(baseUrl: 'http://10.0.0.5:8000', apiKey: 'k', binId: 'bin-001');

ApiRepository _repo(Future<http.Response> Function(http.Request) handler) => ApiRepository(_config, client: MockClient(handler));

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

Map<String, dynamic> _replyJson({
  String reply = 'Add a few handfuls of shredded cardboard.',
  String model = 'gemini-2.5-flash',
  bool onTopic = true,
  bool usedReadings = true,
  String? readingsAt = '2026-10-17T18:04:00+00:00',
  int recentAdds = 3,
  int photos = 2,
}) => {
  'reply': reply,
  'model': model,
  'on_topic': onTopic,
  'used_readings': usedReadings,
  'context': {'readings_at': readingsAt, 'recent_adds': recentAdds, 'photos': photos},
};

void main() {
  group('ApiRepository.askTrunc', () {
    test('reads guarded guidance metadata and tolerates older servers', () async {
      final repo = _repo(
        (_) async => _json({
          ..._replyJson(),
          'need': 'water',
          'context': {'readings_at': null, 'readings_stale': true, 'recent_adds': 0, 'photos': 0},
        }),
      );
      final r = await repo.askTrunc('What next?');
      expect(r.need, BinNeed.water);
      expect(r.context.readingsStale, isTrue);
      final old = await _repo((_) async => _json(_replyJson())).askTrunc('What next?');
      expect(old.need, isNull);
    });
    test('sends the question, the conversation and the photo choice', () async {
      late http.Request seen;
      final repo = _repo((req) async {
        seen = req;
        return _json(_replyJson());
      });

      await repo.askTrunc(
        'Why does it smell sour?',
        history: const [
          TruncTurn(role: TruncRole.user, text: 'Should I add cardboard?'),
          TruncTurn(role: TruncRole.assistant, text: 'Yes, it is a good brown.'),
        ],
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/bins/bin-001/chat');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['message'], 'Why does it smell sour?');
      expect(body['include_photos'], isTrue);
      // Oldest first, and the roles are the names the backend validates.
      expect(body['history'], [
        {'role': 'user', 'text': 'Should I add cardboard?'},
        {'role': 'assistant', 'text': 'Yes, it is a good brown.'},
      ]);
    });

    test('photos can be left out for a cheaper turn', () async {
      late http.Request seen;
      final repo = _repo((req) async {
        seen = req;
        return _json(_replyJson(photos: 0));
      });

      final r = await repo.askTrunc('What are browns?', includePhotos: false);

      expect((jsonDecode(seen.body) as Map)['include_photos'], isFalse);
      expect(r.context.photos, 0);
    });

    test('parses the answer and what it was given', () async {
      final repo = _repo((req) async => _json(_replyJson()));

      final r = await repo.askTrunc('Why does it smell sour?');

      expect(r.reply, 'Add a few handfuls of shredded cardboard.');
      expect(r.model, 'gemini-2.5-flash');
      expect(r.onTopic, isTrue);
      expect(r.usedReadings, isTrue);
      expect(r.isFallback, isFalse);
      expect(r.context.recentAdds, 3);
      expect(r.context.photos, 2);
      expect(r.context.readingsAt?.isUtc, isFalse, reason: 'local for display');
    });

    test('an off-topic answer arrives with the redirect already written', () async {
      final repo = _repo(
        (req) async => _json(_replyJson(reply: "I only know about composting, so I'll stay out of that one.", onTopic: false, usedReadings: false)),
      );

      final r = await repo.askTrunc('Write me a Python script.');

      expect(r.onTopic, isFalse);
      // There is no refusal UI to build: render the reply as a normal message.
      expect(r.reply, contains('only know about composting'));
    });

    test('a rules-fallback answer is flagged but is still a normal reply', () async {
      final repo = _repo((req) async => _json(_replyJson(reply: "I can't reach my brain right now. The top layer is 76% moisture.", model: 'rules-fallback')));

      final r = await repo.askTrunc('Why does it smell?');

      expect(r.isFallback, isTrue);
      expect(r.onTopic, isTrue, reason: 'not an error state');
      expect(r.reply, isNotEmpty);
    });

    test('a bin with no readings yet parses as a null timestamp', () async {
      final repo = _repo((req) async => _json(_replyJson(readingsAt: null, recentAdds: 0, photos: 0)));

      final r = await repo.askTrunc('What are browns?');

      // Null means the answer did not come from this bin -- worth saying
      // quietly in the UI, but not an error.
      expect(r.context.readingsAt, isNull);
      expect(r.onTopic, isTrue);
    });

    test('a missing on_topic defaults to on topic', () async {
      final repo = _repo((req) async => _json({'reply': 'Sure.', 'model': 'm', 'context': {}}));
      expect((await repo.askTrunc('eggshells?')).onTopic, isTrue);
    });

    test('a server error surfaces rather than looking like an answer', () async {
      final repo = _repo((req) async => _json({'detail': 'boom'}, 500));
      await expectLater(repo.askTrunc('hi'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)));
    });
  });

  group('MockRepository.askTrunc', () {
    test('compostability questions include current suitability', () async {
      final r = await MockRepository(Scenario.healthy).askTrunc('Can I compost eggshells?');

      expect(r.onTopic, isTrue);
      expect(r.usedReadings, isTrue, reason: 'suitability is based on the current bin');
      expect(r.reply, isNotEmpty);
    });

    test('leans on the readings when the question is about this bin', () async {
      final r = await MockRepository(Scenario.tooWet).askTrunc('Why does my bin smell?');

      expect(r.usedReadings, isTrue);
      expect(r.reply.toLowerCase(), contains('cardboard'));
      expect(r.context.readingsAt, isNotNull);
    });

    test('the scenario changes the answer, so both branches are reachable', () async {
      final wet = await MockRepository(Scenario.tooWet).askTrunc('Why does my bin smell?');
      final ok = await MockRepository(Scenario.healthy).askTrunc('Why does my bin smell?');
      expect(wet.reply, isNot(ok.reply));
      expect(ok.reply.toLowerCase(), contains('nothing is urgent'));
    });

    test('an off-topic question is refused', () async {
      final r = await MockRepository(Scenario.healthy).askTrunc('Who won the game last night?');
      expect(r.onTopic, isFalse);
      expect(r.reply, contains('only know about composting'));
    });

    test('asking for the fallback produces one, for building that state', () async {
      final r = await MockRepository(Scenario.healthy).askTrunc('test fallback');
      expect(r.isFallback, isTrue);
      expect(r.onTopic, isTrue);
    });

    test('the same question always gives the same answer', () async {
      final repo = MockRepository(Scenario.healthy);
      expect(
        (await repo.askTrunc('Can I compost eggshells?')).reply,
        (await repo.askTrunc('Can I compost eggshells?')).reply,
        reason: 'scripted, not random, so a screenshot is reproducible',
      );
    });

    test('it takes long enough to be worth a typing indicator', () async {
      final started = DateTime.now();
      await MockRepository(Scenario.healthy).askTrunc('Can I compost eggshells?');
      expect(DateTime.now().difference(started).inMilliseconds, greaterThan(500));
    });
  });
}
