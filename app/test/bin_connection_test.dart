import 'dart:async';
import 'dart:convert';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/data/social_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/connection/bin_connection_screen.dart';
import 'package:calmpost/features/drop/drop_sheet.dart';
import 'package:calmpost/features/layers/layers_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/social.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'social_ui_test.dart' show MemoryStore;

const account = SocialSession(server: 'http://localhost:8000', token: 'alice-token', userId: 'alice');
const paired = SocialSession(server: 'http://localhost:8000', token: 'alice-token', userId: 'alice', binId: 'bin-001');
http.Response json(Object value, [int status = 200]) => http.Response(jsonEncode(value), status);

class CameraRepo extends MockRepository {
  CameraRepo() : super(Scenario.healthy) {
    dropDelay = const Duration(seconds: 30);
  }
  int arms = 0;
  @override
  Future<DropSession> startDropSession() {
    arms++;
    return super.startDropSession();
  }

  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
}

void main() {
  setUpAll(() async {
    for (final family in {
      'Manrope': ['500', '600', '700', '800'],
      'Fraunces': ['400', '500'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final weight in family.value) {
        loader.addFont(rootBundle.load('assets/fonts/${family.key}-$weight.ttf'));
      }
      await loader.load();
    }
  });
  test('saved account pairing refreshes repository; unchanged social reads preserve it', () async {
    final store = MemoryStore(account);
    final social = SocialRepository(client: MockClient((r) async => json({'bin_id': 'bin-001'})));
    final c = ProviderContainer(overrides: [sessionStoreProvider.overrideWithValue(store), socialRepositoryProvider.overrideWithValue(social)]);
    addTearDown(c.dispose);
    addTearDown(social.close);
    await c.read(socialSessionProvider.future);
    expect(c.read(needsBinProvider), true);
    final sub = c.listen(socialDataProvider('/me'), (_, _) {});
    await c.read(socialDataProvider('/me').future);
    final repo = c.read(repositoryProvider) as ApiRepository;
    expect(repo.config.binId, 'bin-001');
    expect(repo.config.token, 'alice-token');
    expect(store.value!.binId, 'bin-001');
    expect(c.read(needsBinProvider), false);
    await c.read(socialDataProvider('/me').future);
    c.invalidate(socialDataProvider); // Same invalidation as a friend write.
    await c.read(socialDataProvider('/me').future);
    expect(identical(c.read(repositoryProvider), repo), true);
    c.read(dataSourceProvider.notifier).state = DataSource.mock;
    await c.read(socialSessionProvider.notifier).refreshBin();
    expect(c.read(dataSourceProvider), DataSource.mock);
    sub.close();
  });

  test('late unpaired response cannot undo a successful pairing; failed refresh retains it', () async {
    final response = Completer<http.Response>();
    var fail = false;
    final social = SocialRepository(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/bin')) return json({'bin_id': 'bin-001'});
        if (fail) return json({'detail': 'offline'}, 503);
        return response.future;
      }),
    );
    final c = ProviderContainer(overrides: [sessionStoreProvider.overrideWithValue(MemoryStore(account)), socialRepositoryProvider.overrideWithValue(social)]);
    addTearDown(c.dispose);
    addTearDown(social.close);
    await c.read(socialSessionProvider.future);
    final refresh = c.read(socialSessionProvider.notifier).refreshBin();
    await c.read(socialSessionProvider.notifier).pair('device-token');
    response.complete(json({'bin_id': null}));
    await refresh;
    expect(c.read(socialSessionProvider).value!.binId, 'bin-001');
    fail = true;
    await expectLater(c.read(socialSessionProvider.notifier).refreshBin(), throwsA(isA<SocialFailure>()));
    expect(c.read(socialSessionProvider).value!.binId, 'bin-001');
  });

  test('late pairing cannot replace a different signed-in account', () async {
    final response = Completer<http.Response>();
    final store = MemoryStore(account);
    final social = SocialRepository(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/bin')) return response.future;
        if (r.url.path.endsWith('/login')) return json({'token': 'bob-token', 'user_id': 'bob'});
        return json({'bin_id': 'bob-bin'});
      }),
    );
    final c = ProviderContainer(overrides: [sessionStoreProvider.overrideWithValue(store), socialRepositoryProvider.overrideWithValue(social)]);
    addTearDown(c.dispose);
    addTearDown(social.close);
    await c.read(socialSessionProvider.future);
    final pairing = c.read(socialSessionProvider.notifier).pair('device-token');
    await c.read(socialSessionProvider.notifier).signIn('http://localhost:8000', 'bob', 'password123');
    response.complete(json({'bin_id': 'alice-bin'}));
    await pairing;
    expect(c.read(socialSessionProvider).value!.userId, 'bob');
    expect(store.value!.binId, 'bob-bin');
  });

  testWidgets('unpaired camera opens real pairing form and resumes camera after saving', (t) async {
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final store = MemoryStore(account);
    var tries = 0;
    final social = SocialRepository(
      client: MockClient((r) async {
        expect(r.headers['Authorization'], 'Bearer alice-token');
        expect(r.url.path, '/social/bin');
        tries++;
        if (tries == 1) return json({'detail': 'Bin token not recognised'}, 404);
        expect((jsonDecode(r.body) as Map)['device_token'], 'correct-device-token');
        return json({'bin_id': 'bin-001'});
      }),
    );
    final camera = CameraRepo();
    final c = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        socialRepositoryProvider.overrideWithValue(social),
        repositoryProvider.overrideWithValue(camera),
      ],
    );
    addTearDown(c.dispose);
    addTearDown(social.close);
    await c.read(socialSessionProvider.future);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showDropSheet(context), child: const Text('Open camera')),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open camera'));
    await t.pumpAndSettle();
    expect(find.text('Connect your bin first'), findsOneWidget);
    expect(camera.arms, 0);
    await t.tap(find.text('Connect bin'));
    await t.pumpAndSettle();
    expect(find.byType(BinConnectionScreen), findsOneWidget);
    Future<void> attempt(String token) async {
      await t.ensureVisible(find.byType(TextField));
      await t.enterText(find.byType(TextField), token);
      await t.ensureVisible(find.text('Connect bin').last);
      await t.tap(find.text('Connect bin').last);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await attempt('wrong-token');
    expect(find.text('Bin token not recognised'), findsOneWidget);
    expect(store.value!.binId, isNull);
    await attempt('correct-device-token');
    expect(find.byType(BinConnectionScreen), findsNothing);
    expect(camera.arms, 1);
    expect(store.value!.binId, 'bin-001');
    expect(find.text('Watching the bin…'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.pump(const Duration(seconds: 31));
  });

  testWidgets('Sensors offers connection rather than a misleading retry or spinner', (t) async {
    final c = ProviderContainer(overrides: [sessionStoreProvider.overrideWithValue(MemoryStore(account))]);
    addTearDown(c.dispose);
    await c.read(socialSessionProvider.future);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: LayersScreen()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('No bin connected to this account'), findsOneWidget);
    await t.tap(find.text('Connect bin'));
    await t.pumpAndSettle();
    expect(find.byType(BinConnectionScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
