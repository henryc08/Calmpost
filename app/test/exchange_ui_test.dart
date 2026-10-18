import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/data/social_repository.dart';
import 'package:calmpost/features/social/social_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/social.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Store implements SessionStore {
  @override
  Future<SocialSession?> read() async => const SocialSession(
    server: 'http://localhost:8000',
    token: 'bob-token',
    userId: 'bob',
  );
  @override
  Future<void> write(SocialSession? value) async {}
}

const _material = {
  'id': 'dry_leaves',
  'name': 'Dry leaves',
  'category': 'brown',
  'note': 'Dry material helps balance wet scraps.',
};
Json post({
  String status = 'open',
  String kind = 'request',
  bool firstConfirmed = false,
}) => {
  'id': 1,
  'circle_id': 'crew',
  'kind': kind,
  'material': _material,
  'quantity': 'One small bag',
  'details': 'For the community garden bin.',
  'version': status == 'open' ? 1 : 2,
  'status': status,
  'created_at': DateTime.now().toUtc().toIso8601String(),
  'expires_at': DateTime.now()
      .toUtc()
      .add(const Duration(days: 7))
      .toIso8601String(),
  'creator': {
    'user_id': 'alice',
    'handle': 'alice',
    'display_name': 'Alice Green',
  },
  'responder': status == 'open'
      ? null
      : {'user_id': 'bob', 'handle': 'bob', 'display_name': 'Bob'},
  'creator_confirmed': firstConfirmed,
  'responder_confirmed': false,
  'creator_xp': 0,
  'responder_xp': 0,
  if (status != 'open') 'reservation_id': 'reservation-12345',
  if (status != 'open') 'creator_note': 'Garden gate, Saturday at noon.',
  if (status != 'open') 'responder_note': 'I can bring a bag of leaves.',
};

class _Server {
  List<Json> posts = [post()];
  final writes = <({String path, Json body})>[];
  bool failRead = false, failCreate = false, loseClaim = false;
  Json? savedCreate;
  late final repo = SocialRepository(
    client: MockClient((r) async {
      expect(r.headers['Authorization'], 'Bearer bob-token');
      final path = r.url.path;
      if (r.method == 'GET') {
        if (failRead) {
          return http.Response('{"detail":"Offline right now"}', 503);
        }
        final view = r.url.queryParameters['view'];
        return _json({
          'name': 'Garden crew',
          'owner_id': 'alice',
          'materials': [
            _material,
            {
              'id': 'help_turning',
              'name': 'Help turning a bin',
              'category': 'help',
              'note': '',
            },
          ],
          'posts': posts.where((p) {
            if (view == 'history') {
              return [
                'completed',
                'cancelled',
                'expired',
              ].contains(p['status']);
            }
            if (view == 'mine') {
              return p['creator']['user_id'] == 'bob' ||
                  (p['responder'] as Json?)?['user_id'] == 'bob';
            }
            return ['open', 'reserved'].contains(p['status']);
          }).toList(),
          'next_before': null,
        });
      }
      final body = jsonDecode(r.body) as Json;
      writes.add((path: path, body: body));
      if (path.endsWith('/exchange')) {
        if (failCreate) {
          failCreate = false;
          return http.Response(
            '{"detail":"Save was not confirmed. Retry this same post."}',
            503,
          );
        }
        savedCreate = body;
        final created = {
          ...post(kind: body['kind']),
          'creator': {'user_id': 'bob', 'handle': 'bob', 'display_name': 'Bob'},
          'quantity': body['quantity'],
          'details': body['details'],
        };
        posts = [created];
        return _json(created, 201);
      }
      if (path.endsWith('/claim')) {
        posts = [
          {
            ...post(status: 'reserved'),
            'reservation_id': body['request_id'],
            'responder_note': body['note'],
          },
        ];
        if (loseClaim) {
          loseClaim = false;
          return http.Response(
            '{"detail":"Connection dropped. Retry the reservation."}',
            503,
          );
        }
        return _json(posts.single);
      }
      if (path.endsWith('/confirm')) {
        final current = posts.single;
        posts = [
          {
            ...current,
            'responder_confirmed': true,
            if (current['creator_confirmed'] == true) 'status': 'completed',
            if (current['creator_confirmed'] == true) 'creator_xp': 10,
            if (current['creator_confirmed'] == true) 'responder_xp': 10,
          },
        ];
        return _json(posts.single);
      }
      if (path.endsWith('/release')) {
        posts = [post()];
        return _json(posts.single);
      }
      if (path.endsWith('/cancel')) {
        posts = [
          {...posts.single, 'status': 'cancelled'},
        ];
        return _json(posts.single);
      }
      if (path.endsWith('/note')) {
        posts = [
          {...posts.single, 'responder_note': body['note']},
        ];
        return _json(posts.single);
      }
      return http.Response('{}', 404);
    }),
  );
  http.Response _json(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> fonts() async {
  for (final e in {
    'Manrope': ['500', '600', '700', '800'],
    'Fraunces': ['400', '500'],
  }.entries) {
    final font = FontLoader(e.key);
    for (final w in e.value) {
      font.addFont(rootBundle.load('assets/fonts/${e.key}-$w.ttf'));
    }
    await font.load();
  }
  for (final face in ['Regular', 'Bold', 'Fill']) {
    final font = FontLoader('packages/phosphor_flutter/Phosphor$face');
    font.addFont(
      rootBundle.load(
        'packages/phosphor_flutter/lib/fonts/Phosphor${face == 'Regular' ? '' : '-$face'}.ttf',
      ),
    );
    await font.load();
  }
}

Future<void> _mount(
  WidgetTester t,
  _Server server, {
  double width = 360,
  GlobalKey? screenshot,
}) async {
  t.view.physicalSize = Size(width, 820);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(server.repo.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(_Store()),
        socialRepositoryProvider.overrideWithValue(server.repo),
        repositoryProvider.overrideWithValue(MockRepository(Scenario.healthy)),
        dataSourceProvider.overrideWith((_) => DataSource.mock),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: RepaintBoundary(
          key: screenshot,
          child: const Scaffold(body: ExchangeScreen(circleId: 'crew')),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String text) async {
  final f = find.text(text);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> cleanup(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 21));
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('EXCHANGE_SCREENSHOTS')) return;
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(fonts);
  for (final width in [360.0, 412.0]) {
    testWidgets(
      'request, offer, reserved and completed layouts at ${width}dp large text',
      (t) async {
        final server = _Server()
          ..posts = [
            post(),
            {...post(kind: 'offer'), 'id': 2},
          ];
        final key = GlobalKey();
        await _mount(t, server, width: width, screenshot: key);
        expect(find.text('REQUEST'), findsOneWidget);
        expect(find.text('OFFER'), findsOneWidget);
        await capture(t, key, 'calmpost-exchange-${width.toInt()}-board');
        await t.ensureVisible(find.text('Reserve this offer'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        server.posts = [post(status: 'reserved', firstConfirmed: true)];
        await t.ensureVisible(find.byTooltip('Refresh exchanges'));
        await t.tap(find.byTooltip('Refresh exchanges'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Confirm completed handoff'));
        await t.pumpAndSettle();
        await capture(t, key, 'calmpost-exchange-${width.toInt()}-reserved');
        expect(find.text('PRIVATE HANDOFF NOTES'), findsOneWidget);
        expect(t.takeException(), isNull);
        await tap(t, 'Confirm completed handoff');
        await tap(t, 'Confirm');
        expect(server.writes.last.body, {
          'reservation_id': 'reservation-12345',
        });
        await tap(t, 'History');
        await t.ensureVisible(find.text('Alice Green: 10 XP · Bob: 10 XP'));
        await t.pumpAndSettle();
        expect(find.text('Completed'), findsOneWidget);
        expect(find.text('Confirm completed handoff'), findsNothing);
        expect(t.takeException(), isNull);
        await cleanup(t);
      },
    );
  }
  testWidgets(
    'offer composer validates quantity and retries an unchanged intent',
    (t) async {
      final server = _Server()
        ..posts = []
        ..failCreate = true;
      await _mount(t, server);
      await tap(t, 'Make a request or offer');
      await tap(t, 'I can offer');
      await tap(t, 'Post to group');
      expect(server.writes, isEmpty);
      await t.enterText(find.byType(TextFormField).at(0), 'Two handfuls');
      await t.enterText(
        find.byType(TextFormField).at(1),
        'Spare dry leaves for a neighbour.',
      );
      await tap(t, 'Post to group');
      expect(server.writes.length, 1);
      final first = server.writes.single.body;
      expect(first['kind'], 'offer');
      expect(first['quantity'], 'Two handfuls');
      expect(
        t.widget<TextFormField>(find.byType(TextFormField).at(0)).enabled,
        isFalse,
      );
      await tap(t, 'Retry same post');
      expect(server.writes.length, 2);
      expect(server.writes.last.body, first);
      expect(find.text('Share with your group'), findsNothing);
      expect(find.text('Your post is ready for the group.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await cleanup(t);
    },
  );
  testWidgets(
    'lost claim response retries same reservation, then release allows a new intent',
    (t) async {
      final server = _Server()..loseClaim = true;
      await _mount(t, server);
      await tap(t, 'I can help with this');
      await t.enterText(find.byType(TextFormField), 'Garden gate at noon.');
      await tap(t, 'Reserve');
      expect(server.writes.length, 1);
      final first = server.writes.single.body;
      await tap(t, 'Retry reservation');
      expect(server.writes.last.body, first);
      await tap(t, 'Release reservation');
      await tap(t, 'I can help with this');
      await tap(t, 'Reserve');
      expect(server.writes.last.body['request_id'], isNot(first['request_id']));
      expect(t.takeException(), isNull);
      await cleanup(t);
    },
  );
  testWidgets(
    'first confirmation waits; private notes can be updated; cancelled posts earn no reward',
    (t) async {
      final server = _Server()..posts = [post(status: 'reserved')];
      await _mount(t, server);
      await tap(t, 'Edit your note');
      await t.enterText(find.byType(TextFormField), 'Coming after lunch.');
      await tap(t, 'Save note');
      expect(server.writes.last.body['note'], 'Coming after lunch.');
      await tap(t, 'Confirm completed handoff');
      await tap(t, 'Confirm');
      expect(server.posts.single['status'], 'reserved');
      expect(server.posts.single['responder_xp'], 0);
      expect(
        find.text('You confirmed. Waiting for the other person.'),
        findsOneWidget,
      );
      expect(find.text('Release reservation'), findsNothing);
      await tap(t, 'Close this post');
      await tap(t, 'Confirm');
      await tap(t, 'History');
      expect(find.text('Closed'), findsOneWidget);
      expect(server.posts.single['responder_xp'], 0);
      expect(t.takeException(), isNull);
      await cleanup(t);
    },
  );
  testWidgets('read error retries and rules explain reward limits', (t) async {
    final server = _Server()..failRead = true;
    await _mount(t, server);
    expect(find.text('Offline right now'), findsOneWidget);
    server.failRead = false;
    await tap(t, 'Try again');
    await tap(t, 'How XP works');
    expect(find.text('Useful sharing, rewarded'), findsOneWidget);
    expect(find.textContaining('20 exchange XP'), findsOneWidget);
    expect(t.takeException(), isNull);
    await cleanup(t);
  });
}
