import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/calmpost_repository.dart';
import '../data/mock_repository.dart';
import '../domain/health_score.dart';
import '../domain/models.dart';
import '../domain/xp_rules.dart';
import 'game.dart';

/// Demo scenario for the mock bin. Ignored once ApiRepository is wired in.
final scenarioProvider = StateProvider<Scenario>((ref) => Scenario.healthy);

/// Swap MockRepository for ApiRepository here: the only line that changes.
final repositoryProvider = Provider<CalmpostRepository>((ref) => MockRepository(ref.watch(scenarioProvider)));

final binProvider = StreamProvider<BinSnapshot>((ref) => ref.watch(repositoryProvider).watchBin());

class BinHealth {
  const BinHealth(this.snapshot, this.breakdown, this.mood);
  final BinSnapshot snapshot;
  final HealthBreakdown breakdown;
  final BinMood mood;
  int get score => breakdown.total;
}

final healthProvider = Provider<BinHealth?>((ref) {
  final s = ref.watch(binProvider).valueOrNull;
  if (s == null) return null;
  final b = computeHealth(s);
  return BinHealth(s, b, moodFor(s, b.total));
});

final suggestionProvider = Provider<Suggestion?>((ref) {
  final s = ref.watch(binProvider).valueOrNull;
  if (s == null) return null;
  return ref.watch(repositoryProvider).suggestions(s);
});

class Standing {
  const Standing(this.members, this.yourRank, this.tier);
  final List<LeagueMember> members;
  final int yourRank;
  final LeagueTier tier;
}

final standingsProvider = Provider<Standing>((ref) {
  final weekXp = ref.watch(gameProvider.select((g) => g.weekXp));
  final streak = ref.watch(gameProvider.select((g) => g.streak.days));
  final cohort = ref.watch(repositoryProvider).leagueCohort();
  final you = LeagueMember(name: GameState.playerName, xp: weekXp, colorIndex: 0, isYou: true, streak: streak);
  final all = [...cohort, you]
    ..sort((a, b) {
      final c = b.xp.compareTo(a.xp);
      if (c != 0) return c;
      return a.isYou ? -1 : (b.isYou ? 1 : 0);
    });
  return Standing(all, all.indexWhere((m) => m.isYou) + 1, leagueTiers[GameState.tierIndex]);
});

/// 24 h trend for one zone + metric (sparklines, layer charts).
final trendProvider = FutureProvider.family<List<TrendPoint>, (Zone, Metric)>((ref, key) {
  ref.watch(scenarioProvider);
  return ref.watch(repositoryProvider).trends(key.$1, key.$2);
});

/// Bottom-nav tabs.
enum AppTab { home, layers, log, social, profile }

final tabProvider = StateProvider<AppTab>((ref) => AppTab.home);
