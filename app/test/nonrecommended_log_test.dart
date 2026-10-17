import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calmpost/data/social_repository.dart';
import 'package:calmpost/state/social.dart';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/features/log/verdict_sheet.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionStore implements SessionStore {
  _SessionStore(this.session);
  final SocialSession? session;
  @override
  Future<SocialSession?> read() async => session;
  @override
  Future<void> write(SocialSession? value) async {}
}

void main() {
  for (final signedIn in [false, true]) {
    for (final scale in [1.3, 2.0]) {
      testWidgets('non-recommended banana remains loggable at text scale $scale (account: $signedIn)', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
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
        final repo = MockRepository(Scenario.tooWet);
        final requests = <Json>[];
        final social = SocialRepository(
          client: MockClient((req) async {
            expect(req.url.path, '/social/care-log');
            expect(req.headers['Authorization'], 'Bearer account-token');
            requests.add(jsonDecode(req.body) as Json);
            if (requests.length == 1) return http.Response('{"detail":"Temporarily unavailable"}', 503);
            return http.Response('{"xp_awarded":5,"duplicate":true}', 200);
          }),
        );
        addTearDown(social.close);
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(repo),
              dataSourceProvider.overrideWith((ref) => signedIn ? DataSource.live : DataSource.mock),
              sessionStoreProvider.overrideWithValue(
                _SessionStore(
                  signedIn ? const SocialSession(server: 'http://localhost:8000', token: 'account-token', userId: 'player_test', binId: 'bin-001') : null,
                ),
              ),
              socialRepositoryProvider.overrideWithValue(social),
            ],
            child: MaterialApp(
              theme: buildTheme(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(onPressed: () => showVerdictSheet(context, foodById['banana_peel']!), child: const Text('Open')),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open'));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('Add it carefully'));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Add it carefully').hitTestable(), findsOneWidget);
        final container = ProviderScope.containerOf(t.element(find.text('Add it carefully')));
        expect(container.read(suggestionProvider)!.add.any((f) => f.id == 'banana_peel'), isFalse);
        await t.tap(find.text('Add it carefully'));
        await t.pump(const Duration(seconds: 1));
        if (signedIn) {
          expect(find.text('Temporarily unavailable'), findsOneWidget);
          await t.ensureVisible(find.text('Add it carefully'));
          await t.pump(const Duration(milliseconds: 300));
          await t.tap(find.text('Add it carefully'));
          await t.pump(const Duration(seconds: 1));
          expect(requests, hasLength(2));
          expect(requests[1], requests[0], reason: 'Retry must preserve both amount and request ID');
          expect(requests[0]['catalog_id'], 'banana_peel');
          expect(requests[0]['quantity_g'], 110);
          expect(find.text('Add it carefully'), findsNothing);
        } else {
          expect(container.read(gameProvider).logs.first.item.id, 'banana_peel');
          expect(container.read(gameProvider).logs.first.added, isTrue);
          expect(container.read(gameProvider).logs.first.xp, 5); // volume, no care bonus
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 4));
      });
    }
  }
}
