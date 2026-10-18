import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_config.dart';
import '../data/api_repository.dart';
import '../data/calmpost_repository.dart';
import '../data/mock_repository.dart';
import '../domain/health_score.dart';
import '../domain/models.dart';
import '../domain/inventory.dart';
import '../domain/xp_rules.dart';
import 'game.dart';
import 'social.dart';

/// Demo scenario for the mock bin. Only used while [dataSourceProvider] is mock.
final scenarioProvider = StateProvider<Scenario>((ref) => Scenario.healthy);

final inventoryProvider = FutureProvider.autoDispose.family<CompostInventory, String>((ref, period) async {
  final timer = Timer(const Duration(seconds: 20), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(repositoryProvider).inventory(period: period);
});

/// Live = the real bin through the backend (needs a build with API_URL, see
/// data/api_config.dart). Mock = the demo scenarios. Switch in the demo
/// picker (long-press the Bin World), e.g. if the venue Wi-Fi drops.
enum DataSource { live, mock }

final dataSourceProvider = StateProvider<DataSource>((ref) {
  final account = ref.watch(socialSessionProvider).valueOrNull;
  return account != null || ApiConfig.configured ? DataSource.live : DataSource.mock;
});

final repositoryProvider = Provider<CalmpostRepository>((ref) {
  final account = ref.watch(socialSessionProvider).valueOrNull;
  final source = ref.watch(dataSourceProvider);
  if (source == DataSource.live && account != null) {
    final repo = ApiRepository(ApiConfig(baseUrl: account.server, apiKey: '', binId: account.binId ?? '', userId: account.userId, token: account.token));
    ref.onDispose(repo.close);
    return repo;
  }
  if (source == DataSource.live && account == null && ApiConfig.configured) {
    final repo = ApiRepository(ApiConfig.fromEnvironment());
    ref.onDispose(repo.close);
    return repo;
  }
  return MockRepository(ref.watch(scenarioProvider));
});

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

/// Everyone else in your league this week. Live, it refreshes every 30 s so
/// other players' XP moves; the mock league never changes.
final cohortProvider = FutureProvider<List<LeagueMember>>((ref) {
  final repo = ref.watch(repositoryProvider);
  if (repo is ApiRepository) {
    final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return repo.leagueCohort();
});

class Standing {
  const Standing(this.members, this.yourRank, this.tier);
  final List<LeagueMember> members;
  final int yourRank;
  final LeagueTier tier;

  /// XP of the last place in the promotion zone. A league smaller than the
  /// zone (a new live league, or one still loading) is all promotion zone.
  int get promotionCutoffXp => members[(promoteCount < members.length ? promoteCount : members.length) - 1].xp;
}

final standingsProvider = Provider<Standing>((ref) {
  final weekXp = ref.watch(gameProvider.select((g) => g.weekXp));
  final streak = ref.watch(gameProvider.select((g) => g.streak.days));
  final cohort = ref.watch(cohortProvider).valueOrNull ?? const <LeagueMember>[];
  final you = LeagueMember(name: GameState.playerName, xp: weekXp, colorIndex: 0, isYou: true, streak: streak);
  final all = [...cohort, you]
    ..sort((a, b) {
      final c = b.xp.compareTo(a.xp);
      if (c != 0) return c;
      return a.isYou ? -1 : (b.isYou ? 1 : 0);
    });
  return Standing(all, all.indexWhere((m) => m.isYou) + 1, leagueTiers[ref.watch(gameProvider.select((g) => g.leagueTier))]);
});

/// 24 h trend for one zone + metric (sparklines, layer charts).
final trendProvider = FutureProvider.autoDispose.family<List<TrendPoint>, (Zone, Metric)>((ref, key) {
  ref.watch(scenarioProvider);
  final repo = ref.watch(repositoryProvider);
  if (repo is ApiRepository) {
    final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
    ref.onCancel(timer.cancel);
  }
  return repo.trends(key.$1, key.$2);
});

/// Bottom-nav tabs.
enum AppTab { home, layers, log, social, profile }

final tabProvider = StateProvider<AppTab>((ref) => AppTab.home);

/// Shared with Home so a reading opens the matching sensor view.
final sensorMetricProvider = StateProvider<Metric>((ref) => Metric.moisture);

/// An item another screen wants the Log tab to check (e.g. tapped on Home).
final logIntentProvider = StateProvider<FoodItem?>((ref) => null);
