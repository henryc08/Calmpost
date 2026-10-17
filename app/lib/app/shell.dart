import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../data/mock_repository.dart';
import '../domain/models.dart';
import '../features/home/bin_world.dart';
import '../features/home/home_screen.dart';
import '../state/game.dart';
import '../state/providers.dart';
import '../ui/tokens.dart';
import '../ui/type.dart';
import 'notifications.dart';
import 'toast.dart';

/// Five tabs: Home · Layers · Log · Social · Profile.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _readyNotified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyDevLinks();
      Notifications.init();
    });
  }

  /// Web preview deep links for design review: ?tab=0-4 &scenario=tooWet &checkin=1
  void _applyDevLinks() {
    if (!kIsWeb) return;
    final q = Uri.base.queryParameters;
    final tab = int.tryParse(q['tab'] ?? '');
    if (tab != null && tab >= 0 && tab < AppTab.values.length) ref.read(tabProvider.notifier).state = AppTab.values[tab];
    final s = Scenario.values.where((s) => s.name == q['scenario']).firstOrNull;
    if (s != null) ref.read(scenarioProvider.notifier).state = s;
    if (q['checkin'] == '1') ref.read(gameProvider.notifier).checkIn();
    BinWorld.debugHour = double.tryParse(q['hour'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(tabProvider);

    // Opening Layers counts as checking on the bin.
    ref.listen(tabProvider, (prev, next) {
      if (next == AppTab.layers) ref.read(gameProvider.notifier).checkIn();
    });

    ref.listen(binProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      ref.read(gameProvider.notifier).syncHealthyHours(s.healthyHoursToday);
      final ready = s.bottomStage == Stage.ready;
      if (ready && !_readyNotified) Notifications.compostReady();
      _readyNotified = ready;
    });

    return Scaffold(
      backgroundColor: C.paper,
      body: Stack(
        children: [
          IndexedStack(
            index: tab.index,
            children: const [
              HomeScreen(),
              ComingNext('Layers', 'Live readings and 24-hour charts for\nthe top layer, bottom layer and air gap.'),
              ComingNext('Log', 'Search or snap a scrap and get a\nverdict based on the live readings.'),
              ComingNext('Social', 'Weekly leagues, friends and co-op quests.'),
              ComingNext('Profile', 'Level, achievements, collection and settings.'),
            ],
          ),
          const ToastLayer(),
        ],
      ),
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: _NavBar(current: tab, onTap: (t) => ref.read(tabProvider.notifier).state = t),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.current, required this.onTap});
  final AppTab current;
  final ValueChanged<AppTab> onTap;

  static const _items = {
    AppTab.home: ('Home', PhosphorIconsRegular.house, PhosphorIconsFill.house),
    AppTab.layers: ('Layers', PhosphorIconsRegular.stack, PhosphorIconsFill.stack),
    AppTab.log: ('Log', PhosphorIconsRegular.plus, PhosphorIconsBold.plus),
    AppTab.social: ('Social', PhosphorIconsRegular.usersThree, PhosphorIconsFill.usersThree),
    AppTab.profile: ('Profile', PhosphorIconsRegular.userCircle, PhosphorIconsFill.userCircle),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(top: BorderSide(color: C.line)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            for (final e in _items.entries)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: e.key == current,
                  label: e.value.$1,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (e.key != current) HapticFeedback.selectionClick();
                      onTap(e.key);
                    },
                    child: e.key == AppTab.log
                        ? _LogButton(active: current == AppTab.log)
                        : _Item(label: e.value.$1, icon: e.key == current ? e.value.$3 : e.value.$2, active: e.key == current),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.label, required this.icon, required this.active});
  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? C.ink : C.muted;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 23, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: T.small.copyWith(fontSize: 11, color: color, fontWeight: active ? FontWeight.w700 : FontWeight.w600),
        ),
      ],
    );
  }
}

class _LogButton extends StatelessWidget {
  const _LogButton({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: M.base,
        width: 52,
        height: 40,
        decoration: BoxDecoration(color: active ? C.forest2 : C.forest, borderRadius: BorderRadius.circular(R.pill)),
        child: const Icon(PhosphorIconsBold.plus, color: C.onForest, size: 20),
      ),
    );
  }
}
