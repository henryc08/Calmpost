import 'dart:async';

import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/features/home/today_quests.dart';
import 'package:calmpost/state/celebrations.dart';
import 'package:calmpost/state/game.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> rewardBundle({int loam = 100, bool claimed = false, int packets = 2}) => {
  'profile': {
    'total_xp': 15,
    'week_xp': 15,
    'loam': loam,
    'streak_days': 1,
    'lid_locks': 0,
    'best_streak': 1,
    'care_days': [],
    'lock_days': [],
    'achievements': [],
    'daily_goal': {'xp_today': 15, 'goals': []},
    'packets': packets,
    'impact': {'kg_diverted': 0},
  },
  'collection': {
    'items': [],
    'pity': {'since_epic': 0, 'since_legendary': 0},
  },
  'rewards': {'crates': []},
  'quests': {
    'quests': [
      {'key': 'checkin', 'progress': 1, 'claimed': claimed},
    ],
  },
  'logs': [],
  'league': null,
};

class RewardRepo extends MockRepository {
  RewardRepo() : super(Scenario.healthy);
  @override
  bool get serverGame => true;
  final actions = <String>[];
  final arguments = <Map<String, dynamic>>[];
  final writes = <Completer<Map<String, dynamic>>>[];
  final reads = <Completer<Map<String, dynamic>>>[];
  bool delayReads = false;
  bool claimed = false;
  int packets = 2;
  @override
  Future<Map<String, dynamic>> loadGame() async {
    if (!delayReads) return rewardBundle(claimed: claimed, packets: packets);
    final read = Completer<Map<String, dynamic>>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<Map<String, dynamic>> gameAction(String action, Map<String, dynamic> args) async {
    actions.add(action);
    arguments.add(args);
    final write = Completer<Map<String, dynamic>>();
    writes.add(write);
    return write.future;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('a quest and a purchase wait for check-in instead of losing taps; duplicate quest sends once', () async {
    final repo = RewardRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    await flush();
    final checkin = game.checkInAsync();
    await flush();
    final quest = game.claimQuestAsync('checkin');
    await game.claimQuestAsync('checkin');
    final purchase = game.buyLidLockAsync();
    expect(repo.actions, ['check-in']);
    expect(c.read(gameActionsProvider), {'check-in', 'quest:checkin', 'lid-lock'});
    repo.writes[0].complete({'xp_awarded': 5});
    await checkin;
    await flush();
    expect(repo.actions, ['check-in', 'quest']);
    repo.claimed = true;
    repo.writes[1].complete({'xp_awarded': 10, 'loam_awarded': 10});
    await quest;
    expect(c.read(toastProvider)!.message, 'Quest claimed · +10 Loam');
    await flush();
    repo.writes[2].complete({});
    expect(await purchase, true);
    expect(c.read(gameActionsProvider), isEmpty);
  });

  test('failed action releases queue and permits explicit retry', () async {
    final repo = RewardRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    await flush();
    final quest = game.claimQuestAsync('checkin');
    final purchase = game.buyLidLockAsync();
    await flush();
    repo.writes[0].completeError(StateError('offline'));
    await quest;
    await flush();
    expect(repo.actions, ['quest', 'lid-lock']);
    repo.writes[1].complete({});
    expect(await purchase, true);
    final retry = game.claimQuestAsync('checkin');
    await flush();
    repo.writes[2].complete({'xp_awarded': 10, 'loam_awarded': 10});
    await retry;
    expect(repo.actions, ['quest', 'lid-lock', 'quest']);
  });

  test('account switch cancels unsent actions and ignores old response without blocking new account', () async {
    final old = RewardRepo();
    final next = RewardRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(old)]);
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    await flush();
    final first = game.checkInAsync();
    final queued = game.claimQuestAsync('checkin');
    await flush();
    c.updateOverrides([repositoryProvider.overrideWithValue(next)]);
    final newGame = c.read(gameProvider.notifier);
    await flush();
    expect(c.read(gameActionsProvider), isEmpty);
    final fresh = newGame.buyLidLockAsync();
    await flush();
    next.writes.single.complete({});
    expect(await fresh, true);
    old.writes.single.complete({'xp_awarded': 5});
    await Future.wait([first, queued]);
    expect(old.actions, ['check-in']);
    expect(next.actions, ['lid-lock']);
    expect(c.read(gameActionsProvider), isEmpty);
  });

  testWidgets('quest shows Claiming then Claimed, sends one request for rapid taps', (tester) async {
    final repo = RewardRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: TodayQuests()),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Claim'));
    await tester.tap(find.text('Claim'));
    await tester.pump();
    expect(find.text('Claiming…'), findsOneWidget);
    expect(repo.actions, ['quest']);
    repo.claimed = true;
    repo.writes.single.complete({'xp_awarded': 10, 'loam_awarded': 10});
    await tester.pump();
    expect(find.text('Claimed'), findsOneWidget);
  });
}
