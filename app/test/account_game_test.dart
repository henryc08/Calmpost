import 'dart:convert';
import 'package:calmpost/data/api_config.dart';
import 'package:calmpost/data/api_repository.dart';
import 'package:calmpost/data/social_repository.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/social.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemorySession implements SessionStore {
  const MemorySession(this.bin);
  final String? bin;
  @override
  Future<SocialSession?> read() async => SocialSession(server: 'http://bin.test', token: 'player-token', userId: 'player_test', binId: bin);
  @override
  Future<void> write(SocialSession? value) async {}
}

void main() {
  test('paired and unpaired accounts select a server game, never seeded progress', () async {
    for (final bin in <String?>['bin-001', null]) {
      final c = ProviderContainer(overrides: [sessionStoreProvider.overrideWithValue(MemorySession(bin))]);
      await c.read(socialSessionProvider.future);
      expect(c.read(dataSourceProvider), DataSource.live);
      final repo = c.read(repositoryProvider) as ApiRepository;
      expect(repo.serverGame, isTrue);
      expect(repo.config.binId, bin ?? '');
      c.dispose();
    }
  });

  test('account game loads real logs and rewards; check-in uses Social', () async {
    final paths = <String>[];
    final repo = ApiRepository(
      const ApiConfig(baseUrl: 'http://bin.test', apiKey: '', token: 'player-token', userId: 'player_test'),
      client: MockClient((r) async {
        expect(r.headers['Authorization'], 'Bearer player-token');
        paths.add(r.url.path);
        final Object response;
        switch (r.url.path) {
          case '/users/player_test/game':
            response = {
              'total_xp': 12, 'week_xp': 12, 'loam': 0, 'streak_days': 0, 'lid_locks': 0,
              'best_streak': 0, 'care_days': [], 'lock_days': [], 'achievements': [],
              'daily_goal': {'xp_today': 12, 'goals': []}, 'packets': 0,
              'impact': {'kg_diverted': .25}, 'grams_today': 250,
              'equipped_seed': 'sprout', 'level_claimed': [1],
            };
          case '/users/player_test/rewards':
            response = {'crates': []};
          case '/users/player_test/collection':
            response = {'items': [{'id': 'sprout', 'copies': 1}], 'pity': {'since_epic': 0, 'since_legendary': 0}};
          case '/quests/today':
            response = {'quests': []};
          case '/bins/bin-001/logs':
            response = [{'catalog_id': 'banana_peel', 'category': 'green', 'item': 'Banana peel', 'time': DateTime.now().toUtc().toIso8601String(), 'action': 'added', 'quantity_g': 250, 'xp_awarded': 12}];
          case '/leagues/current':
            return http.Response('{}', 404);
          case '/social/check-in':
            response = {'xp_awarded': 5};
          case '/users/player_test/levels/1/claim':
            response = {'duplicate': true};
          default:
            throw StateError('Unexpected request ${r.url.path}');
        }
        return http.Response(jsonEncode(response), 200);
      }),
    );
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    addTearDown(repo.close);
    final initial = c.read(gameProvider);
    expect(initial.logs, isEmpty);
    expect(initial.loam, 0);
    expect(initial.kgDiverted, 0);
    await c.read(gameProvider.notifier).refreshLive();
    final loaded = c.read(gameProvider);
    expect(loaded.logs.single.item.id, 'banana_peel');
    expect(loaded.logs.single.quantityG, 250);
    expect(loaded.totalXp, 12);
    expect(loaded.kgDiverted, .25);
    expect(loaded.loam, 0);
    expect(loaded.activeSeed, 'sprout');
    expect(loaded.levelClaimed, {1});
    await repo.gameAction('level', {'level': 1});
    expect(paths, contains('/users/player_test/levels/1/claim'));
    await repo.gameAction('check-in', {});
    expect(paths, contains('/social/check-in'));
    expect(paths, isNot(contains('/users/player_test/check-in')));
  });
}
