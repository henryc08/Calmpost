import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/data/social_repository.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/social.dart';
import 'package:calmpost/data/toronto_repository.dart';
import 'package:calmpost/domain/advice_rules.dart';
import 'package:calmpost/domain/toronto.dart';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/state/toronto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingStore extends TorontoProgressStore {
  FailingStore() : super(null, 'failure');
  @override
  Future<void> write(TorontoProgress progress) async =>
      throw StateError('disk full');
}

class SwitchingAccountStore implements SessionStore {
  SocialSession? value;
  @override
  Future<SocialSession?> read() async => value;
  @override
  Future<void> write(SocialSession? session) async {
    value = session;
  }
}

class DelayedStore extends TorontoProgressStore {
  DelayedStore() : super(null, 'old-account');
  final completed = Completer<void>();
  @override
  Future<void> write(TorontoProgress progress) => completed.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TorontoData data;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    data = await TorontoRepository().load();
  });
  test('reviewed answers trace to City records and current guidance', () {
    final source =
        (jsonDecode(
                  File(
                    '../testdata/toronto/waste_wizard_subset.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<Map<String, dynamic>>();
    expect(data.items.length, 24);
    expect(data.provenance['source_records'], 2206);
    expect(data.provenance['resource_modified'], startsWith('2023-12-12'));
    expect(data.stats['multi_residential_diversion_pct'], 26.3);
    expect(data.stats['single_family_diversion_pct'], 60.3);
    for (final item in data.items) {
      final original = source.singleWhere((r) => r['id'] == item.id);
      expect(item.sourceItem, original['item']);
      expect(item.sourceCategory, original['category']);
      expect(data.sources.containsKey(item.source), true);
    }
    expect(data.forCatalog('cheese')!.route, TorontoRoute.green);
    expect(data.forCatalog('bones')!.route, TorontoRoute.green);
    expect(data.forCatalog('grass')!.route, TorontoRoute.lawn);
    expect(data.byId('A0688').route, TorontoRoute.garbage);
    expect(data.byId('A0304').route, TorontoRoute.recycling);
    expect(data.byId('A1447').action, contains('chemicals'));
    expect(
      data.forCatalog('oily_food')!.action,
      contains('not a container of liquid'),
    );
  });
  test('unknowns never get routes from compost categories or loose labels', () {
    expect(data.forCatalog('custom:chicken soup'), isNull);
    expect(data.forCatalog('sawdust'), isNull);
    expect(data.search('cheese rind').single.id, 'A1334');
    expect(data.search('compostable cup').single.route, TorontoRoute.garbage);
    expect(data.search('battery'), isEmpty);
    expect(data.search('banana plastic'), isEmpty);
  });
  test('municipal answers leave bin safety intact', () async {
    final repo = MockRepository(Scenario.healthy);
    final snapshot = await repo.watchBin().first;
    for (final id in ['cheese', 'bones', 'meat', 'fish', 'oily_food']) {
      expect(
        adviseFor(foodById[id]!, snapshot, foodById).verdict,
        Verdict.avoid,
      );
      expect(data.forCatalog(id)!.route, TorontoRoute.green);
    }
  });
  test('first attempts are immutable, ordered and transfer needs lessons', () {
    var p = TorontoProgress();
    expect(
      p.answer('A1318', TorontoRoute.green, followUp: true).after,
      isEmpty,
    );
    expect(p.learn('food').learned, isEmpty);
    expect(
      p.answer('A0688', TorontoRoute.green, followUp: false).before,
      isEmpty,
    );
    for (final q in torontoBefore) {
      p = p.answer(q.itemId, TorontoRoute.garbage, followUp: false);
    }
    final original = p.before['A1334'];
    p = p.answer('A1334', TorontoRoute.green, followUp: false);
    expect(p.before['A1334'], original);
    expect(p.answer('unknown', TorontoRoute.green, followUp: false), same(p));
    expect(
      p.answer('A1318', TorontoRoute.green, followUp: true).after,
      isEmpty,
    );
    for (final l in torontoLessons) {
      p = p.learn(l.id);
    }
    for (final q in torontoAfter) {
      p = p.answer(q.itemId, data.byId(q.itemId).route, followUp: true);
    }
    expect(p.complete, true);
    expect(data.score(p.after, torontoAfter), 3);
    expect(TorontoProgress.fromJson(p.toJson()).complete, true);
  });
  test(
    'local practice is idempotent and scoped to guest or each account',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final guest = TorontoProgressStore(prefs, 'guest');
      final owner = TorontoProgressStore(prefs, 'https://example.test|owner');
      final other = TorontoProgressStore(prefs, 'https://example.test|other');
      final p = TorontoProgress().apply('A1334').apply('A1334');
      await owner.write(p);
      expect(owner.read().applied.length, 1);
      expect(guest.read().applied, isEmpty);
      expect(other.read().applied, isEmpty);
      expect(p.toJson().keys, isNot(contains('xp')));
      expect(p.toJson().keys, isNot(contains('grams')));
      await owner.reset();
      expect(owner.read().applied, isEmpty);
    },
  );
  test(
    'failed saves retain evidence and corrupt storage is surfaced',
    () async {
      final notifier = TorontoProgressNotifier(FailingStore());
      expect(await notifier.save((p) => p.apply('A1334')), false);
      expect(notifier.state.requireValue.applied, isEmpty);
      notifier.dispose();
      final prefs = await SharedPreferences.getInstance();
      final store = TorontoProgressStore(prefs, 'corrupt');
      await prefs.setString(store.key, '{');
      final broken = TorontoProgressNotifier(store);
      expect(broken.state.hasError, true);
      expect(await broken.reset(), true);
      expect(broken.state.requireValue.before, isEmpty);
      broken.dispose();
    },
  );
  test('account transitions keep guest and user learning separate', () async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = SwitchingAccountStore();
    final c = ProviderContainer(
      overrides: [
        gameStorageProvider.overrideWithValue(prefs),
        sessionStoreProvider.overrideWithValue(accounts),
      ],
    );
    addTearDown(c.dispose);
    await c.read(socialSessionProvider.future);
    await c
        .read(torontoProgressProvider.notifier)
        .save((p) => p.apply('A1334'));
    accounts.value = const SocialSession(
      server: 'https://example.test',
      token: 'private-token',
      userId: 'one',
    );
    c.invalidate(socialSessionProvider);
    await c.read(socialSessionProvider.future);
    expect(c.read(torontoProgressProvider).requireValue.applied, isEmpty);
    await c
        .read(torontoProgressProvider.notifier)
        .save((p) => p.apply('A1318'));
    expect(
      c.read(torontoProgressProvider.notifier).store.key,
      isNot(contains('private-token')),
    );
    accounts.value = null;
    c.invalidate(socialSessionProvider);
    await c.read(socialSessionProvider.future);
    expect(c.read(torontoProgressProvider).requireValue.applied, {'A1334'});
  });
  test(
    'late saves cannot update disposed state and account errors cannot reset guest',
    () async {
      final store = DelayedStore();
      final old = TorontoProgressNotifier(store);
      final saving = old.save((p) => p.apply('A1334'));
      expect(await old.save((p) => p.apply('A1318')), false);
      old.dispose();
      store.completed.complete();
      expect(await saving, false);
      final blocked = TorontoProgressNotifier(
        TorontoProgressStore(await SharedPreferences.getInstance(), 'guest'),
        accountUnavailable: true,
      );
      expect(blocked.state.hasError, true);
      expect(await blocked.reset(), false);
      blocked.dispose();
    },
  );
}
