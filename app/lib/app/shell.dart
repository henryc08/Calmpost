import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../domain/models.dart';
import '../domain/xp_rules.dart';
import '../features/celebrations/celebration_screen.dart';
import '../features/home/home_screen.dart';
import '../features/journey/journey_screen.dart';
import '../features/leagues/leagues_screen.dart';
import '../features/profile/profile_screen.dart';
import '../state/celebrations.dart';
import '../state/game.dart';
import '../state/providers.dart';
import '../ui/ui.dart';
import 'dev_hooks.dart';
import 'notifications.dart';
import 'routes.dart';
import 'toast_layer.dart';

/// Tabs + the game's event loop (celebrations, quest syncing, ready alerts).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = DevHooks.initialTab();
  bool _showing = false;
  bool _readyShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DevHooks.apply(context, ref);
      Notifications.init();
    });
  }

  static const _tabs = [
    TabItem(PhosphorIconsFill.house, Tone.leaf, 'Home'),
    TabItem(PhosphorIconsFill.path, Tone.flame, 'Journey'),
    TabItem(PhosphorIconsFill.shieldStar, Tone.moss, 'Leagues'),
    TabItem(PhosphorIconsFill.plant, Tone.sky, 'Profile'),
  ];

  Future<void> _drain() async {
    if (_showing || !mounted) return;
    final queue = ref.read(celebrationProvider);
    if (queue.isEmpty) return;
    _showing = true;
    await Navigator.of(context).push(celebrationRoute(queue.first));
    ref.read(celebrationProvider.notifier).pop();
    _showing = false;
    if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(celebrationProvider, (prev, next) {
      if (next.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
    });

    ref.listen(binProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      ref.read(gameProvider.notifier).syncHealthyHours(s.healthyHoursToday);
      final ready = s.bottomStage == Stage.ready;
      if (ready && !_readyShown) {
        _readyShown = true;
        ref.read(celebrationProvider.notifier).push(const ReadyCelebration());
        Notifications.compostReady();
      } else if (!ready) {
        _readyShown = false;
      }
    });

    ref.listen(standingsProvider.select((s) => s.yourRank), (prev, next) {
      if (prev != null && prev > promoteCount && next <= promoteCount) {
        ref.read(celebrationProvider.notifier).push(PromotionZoneCelebration(next, ref.read(standingsProvider).tier.name));
      }
    });

    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: const [HomeScreen(), JourneyScreen(), LeaguesScreen(), ProfileScreen()]),
          const ToastLayer(),
        ],
      ),
      bottomNavigationBar: TabBarCalm(items: _tabs, index: _index, onTap: (i) => setState(() => _index = i), onCenter: () => Routes.log(context)),
    );
  }
}
