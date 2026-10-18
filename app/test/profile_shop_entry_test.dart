import 'dart:async';
import 'dart:convert';

import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/data/social_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/greenhouse/greenhouse_screen.dart';
import 'package:calmpost/features/profile/profile_screen.dart';
import 'package:calmpost/main.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/social.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'shop_actions_test.dart' show loadShopFonts;
import 'social_ui_test.dart' show MemoryStore;

class _Repo extends MockRepository {
  _Repo() : super(Scenario.healthy);
  @override
  Stream<BinSnapshot> watchBin() => super.watchBin().take(1);
}

class _Account extends SocialAccount {
  void change(SocialSession? next) => state = AsyncData(next);
}

void viewport(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadShopFonts);
  for (final width in [360.0, 412.0]) {
    testWidgets('profile shows account name and opens shop at $width with large text', (t) async {
      viewport(t, width);
      const account = SocialSession(server: 'http://localhost:8000', token: 'test', userId: 'alice');
      var fail = false;
      final social = SocialRepository(
        client: MockClient((r) async {
          if (fail) return http.Response('{"detail":"offline"}', 503);
          return http.Response(jsonEncode({'user_id': 'alice', 'display_name': 'Alexandra the balcony gardener'}), 200);
        }),
      );
      final c = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(MemoryStore(account)),
          socialRepositoryProvider.overrideWithValue(social),
          repositoryProvider.overrideWithValue(_Repo()),
        ],
      );
      addTearDown(social.close);
      await c.read(socialSessionProvider.future);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(),
            home: const Scaffold(body: ProfileScreen()),
          ),
        ),
      );
      await settle(t);
      expect(find.text('Alexandra the balcony gardener'), findsOneWidget);
      expect(find.text('You'), findsNothing);
      expect(t.takeException(), isNull);
      fail = true;
      c.invalidate(socialDataProvider('/me'));
      await settle(t);
      expect(find.text('Alexandra the balcony gardener'), findsOneWidget);
      await t.ensureVisible(find.text('Shop Seed Packets'));
      await t.tap(find.text('Shop Seed Packets'));
      await settle(t);
      expect(find.byType(GreenhouseScreen), findsOneWidget);
      expect(find.text('1 pull'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('Home has a labeled shop entry at $width with large text', (t) async {
      viewport(t, width);
      final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(_Repo()), sessionStoreProvider.overrideWithValue(MemoryStore(null))]);
      await t.pumpWidget(UncontrolledProviderScope(container: c, child: const CalmpostApp()));
      await settle(t);
      expect(find.text('Shop Seed Packets'), findsOneWidget);
      await t.ensureVisible(find.text('Shop Seed Packets'));
      await t.tap(find.text('Shop Seed Packets'));
      await settle(t);
      expect(find.byType(GreenhouseScreen), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('switching accounts never displays the previous name while loading', (t) async {
    final second = Completer<http.Response>();
    const first = SocialSession(server: 'http://localhost:8000', token: 'first', userId: 'alice');
    const next = SocialSession(server: 'http://localhost:8000', token: 'second', userId: 'bob');
    final social = SocialRepository(
      client: MockClient(
        (r) async => r.headers['Authorization'] == 'Bearer first' ? http.Response('{"user_id":"alice","display_name":"Alice Green"}', 200) : second.future,
      ),
    );
    final notifier = _Account();
    final c = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(MemoryStore(first)),
        socialSessionProvider.overrideWith(() => notifier),
        socialRepositoryProvider.overrideWithValue(social),
        repositoryProvider.overrideWithValue(_Repo()),
      ],
    );
    addTearDown(social.close);
    await c.read(socialSessionProvider.future);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await settle(t);
    expect(find.text('Alice Green'), findsOneWidget);
    notifier.change(next);
    await t.pump();
    expect(find.text('Alice Green'), findsNothing);
    expect(find.text('Your profile'), findsOneWidget);
    second.complete(http.Response('{"user_id":"bob","display_name":"Bob Brown"}', 200));
    await settle(t);
    expect(find.text('Bob Brown'), findsOneWidget);
    notifier.change(null);
    await settle(t);
    expect(find.text('Demo gardener'), findsOneWidget);
    expect(find.text('Bob Brown'), findsNothing);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.pump(const Duration(seconds: 5));
  });
}
