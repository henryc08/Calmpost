import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calmpost/data/social_repository.dart';
import 'package:calmpost/features/social/social_screen.dart';
import 'package:calmpost/state/social.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:calmpost/ui/tokens.dart';

class MemoryStore implements SessionStore {
  MemoryStore(this.value);
  SocialSession? value;
  @override
  Future<SocialSession?> read() async => value;
  @override
  Future<void> write(SocialSession? v) async {
    value = v;
  }
}

const session = SocialSession(
  server: 'http://localhost:8000',
  token: 'test-token',
  userId: 'alice',
);
Json person(String id, {bool private = false}) => {
  'user_id': id,
  'handle': id,
  'display_name': id == 'alice'
      ? 'Alice Green'
      : 'Benjamin the balcony gardener',
  'bio': 'Growing good habits, one day at a time.',
  'is_private': private,
  'is_self': id == 'alice',
  'can_view': !private,
  'relationship': 'none',
  'followers': 3,
  'following': 4,
  if (!private)
    'progress': {
      'level': 3,
      'total_xp': 180,
      'week_xp': 45,
      'streak': 7,
      'best_streak': 12,
      'harvests': 1,
      'care_days': [DateTime.now().toUtc().toIso8601String().substring(0, 10)],
      'checked_in_today': false,
    },
};
Json group = {
  'id': 'crew',
  'name': 'The balcony growers',
  'owner_id': 'alice',
  'team_xp': 90,
  'members': [
    {
      'user_id': 'alice',
      'handle': 'alice',
      'display_name': 'Alice Green',
      'xp': 45,
      'rank': 1,
      'is_you': true,
    },
    {
      'user_id': 'bob',
      'handle': 'bob',
      'display_name': 'Benjamin the balcony gardener',
      'xp': 45,
      'rank': 1,
      'is_you': false,
    },
  ],
};

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

ProviderContainer? activeContainer;
Future<void> cleanup(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  activeContainer?.dispose();
  activeContainer = null;
  await t.pump();
}

Future<ProviderContainer> mount(
  WidgetTester t,
  Widget child, {
  bool signedIn = true,
  List<http.Request>? requests,
  GlobalKey? screenshot,
}) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final repo = SocialRepository(
    client: MockClient((r) async {
      requests?.add(r);
      dynamic data = {};
      final path = r.url.path;
      if (path == '/social/me' || path == '/social/people/alice') {
        data = person('alice');
      } else if (path == '/social/people/bob') {
        data = person('bob', private: true);
      } else if (path == '/social/people/bob/follow') {
        data = person('bob', private: true);
      } else if (path == '/social/people') {
        data = [person('bob', private: true)];
      } else if (path == '/social/circles') {
        data = r.method == 'POST'
            ? {'id': 'crew'}
            : [
                {'id': 'crew', 'name': group['name'], 'members': 2},
              ];
      } else if (path == '/social/circles/crew') {
        data = group;
      } else if (path.endsWith('/invite') || path == '/social/invites') {
        data = {'code': 'F-a-long-private-invite-code'};
      } else if (path == '/social/connections') {
        data = [
          {
            ...person('bob', private: true),
            'incoming': true,
            'accepted': false,
          },
        ];
      } else if (path == '/social/feed') {
        data = [
          {
            'id': 1,
            'user_id': 'bob',
            'display_name': 'Benjamin the balcony gardener',
            'handle': 'bob',
            'time': DateTime.now().toUtc().toIso8601String(),
            'kind': 'check_in',
            'xp': 5,
            'cheers': 2,
            'cheered': false,
          },
        ];
      } else if (path == '/social/check-in') {
        data = {'xp_awarded': 5};
      } else if (path == '/social/join') {
        data = {'circle_id': 'crew'};
      } else if (path == '/social/register' || path == '/social/login') {
        data = {'token': 'new-token', 'user_id': 'alice'};
      }
      return http.Response(jsonEncode(data), 200);
    }),
  );
  final container = ProviderContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(
        MemoryStore(signedIn ? session : null),
      ),
      socialRepositoryProvider.overrideWithValue(repo),
    ],
  );
  activeContainer = container;
  addTearDown(() {
    activeContainer?.dispose();
    activeContainer = null;
  });
  addTearDown(repo.close);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: RepaintBoundary(
            key: screenshot,
            child: ColoredBox(color: C.paper, child: child),
          ),
        ),
      ),
    ),
  );
  await settle(t);
  return container;
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });
  setUpAll(() async {
    for (final family in {
      'Manrope': ['500', '600', '700', '800'],
      'Fraunces': ['400', '500'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final w in family.value) {
        loader.addFont(rootBundle.load('assets/fonts/${family.key}-$w.ttf'));
      }
      await loader.load();
    }
  });
  testWidgets(
    'activity, invite, people and groups fit at 360dp and large text',
    (t) async {
      final requests = <http.Request>[];
      final shot = GlobalKey();
      await mount(
        t,
        const SocialScreen(),
        requests: requests,
        screenshot: shot,
      );
      expect(find.text('Grow together'), findsOneWidget);
      await t.tap(find.text('Invite a friend'));
      await settle(t);
      expect(find.text('Copy invite code'), findsOneWidget);
      await t.tap(find.text('Copy invite code'));
      await t.pumpAndSettle();
      expect(find.text('Copy invite code'), findsNothing);
      await t.tap(find.text('People'));
      await settle(t);
      await t.scrollUntilVisible(
        find.text('Accept'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.text('Accept'));
      await settle(t);
      await t.tap(find.text('Accept'));
      await settle(t);
      expect(
        requests.any(
          (r) => r.url.path == '/social/requests/bob' && r.method == 'POST',
        ),
        isTrue,
      );
      await t.drag(find.byType(Scrollable).first, const Offset(0, 1500));
      await settle(t);
      await t.tap(find.text('Groups'));
      await settle(t);
      await t.scrollUntilVisible(
        find.text('The balcony growers'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(t.takeException(), isNull);
      await t.tap(find.text('The balcony growers'));
      await settle(t);
      expect(find.text('YOUR LEADERBOARD'), findsOneWidget);
      expect(find.text('45 XP'), findsNWidgets(2));
      expect(t.takeException(), isNull);
      await cleanup(t);
      await t.pump(const Duration(seconds: 1));
    },
  );
  testWidgets('private profile hides progress and submits follow request', (
    t,
  ) async {
    final requests = <http.Request>[];
    await mount(t, const PersonScreen(id: 'bob'), requests: requests);
    expect(find.text('A private growing space'), findsOneWidget);
    expect(find.text('CARE PROGRESS'), findsNothing);
    await t.tap(find.text('Request to follow'));
    await settle(t);
    expect(
      requests.any(
        (r) => r.url.path == '/social/people/bob/follow' && r.method == 'POST',
      ),
      isTrue,
    );
    expect(t.takeException(), isNull);
    await cleanup(t);
  });
  testWidgets('own progress check-in is saved and calendar fits', (t) async {
    final requests = <http.Request>[];
    await mount(t, const PersonScreen(id: 'alice'), requests: requests);
    await t.scrollUntilVisible(
      find.text('I checked on my compost'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.text('I checked on my compost'));
    await settle(t);
    await t.tap(find.text('I checked on my compost'));
    await settle(t);
    expect(requests.any((r) => r.url.path == '/social/check-in'), isTrue);
    expect(t.takeException(), isNull);
    await cleanup(t);
  });
  testWidgets('onboarding validates before creating an account', (t) async {
    await mount(t, const SocialScreen(), signedIn: false);
    expect(find.text('Better together'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Create account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.text('Create account'));
    await t.drag(find.byType(Scrollable).first, const Offset(0, -160));
    await settle(t);
    await t.tap(find.text('Create account'));
    await settle(t);
    expect(find.text('Use at least 10 characters'), findsOneWidget);
    expect(t.takeException(), isNull);
    await cleanup(t);
  });
  testWidgets('capture private leaderboard for visual review', (t) async {
    final key = GlobalKey();
    await mount(t, const CircleScreen(id: 'crew'), screenshot: key);
    expect(t.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${Directory.systemTemp.path}/calmpost-multiplayer-leaderboard.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await cleanup(t);
  });
}
