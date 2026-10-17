import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../data/mock_repository.dart';
import '../data/photo_input.dart';
import '../domain/models.dart';
import '../features/home/bin_world.dart';
import '../features/home/home_screen.dart';
import '../features/layers/layers_screen.dart';
import '../features/log/log_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/social/social_screen.dart';
import '../state/game.dart';
import '../state/providers.dart';
import '../ui/backdrop.dart';
import '../ui/tokens.dart';
import '../ui/type.dart';
import 'notifications.dart';
import 'routes.dart';
import '../features/greenhouse/pull_reveal.dart';
import 'toast.dart';

/// Five tabs: Home · Layers · Log · Social · Profile.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _readyNotified = false;
  Timer? _gameTick;

  @override
  void initState() {
    super.initState();
    _gameTick = Timer.periodic(const Duration(minutes: 1), (_) => ref.read(gameProvider.notifier).tick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyDevLinks();
      Notifications.init();
    });
  }

  @override
  void dispose() {
    _gameTick?.cancel();
    super.dispose();
  }

  /// Web preview deep links for design review: ?tab=0-4 &scenario=tooWet &checkin=1 &source=mock|live
  /// &drop=banana|check|mixed|unclear|nothing (opens the camera drop-in on the mock)
  void _applyDevLinks() {
    if (!kIsWeb || ref.read(repositoryProvider).serverGame) return;
    final q = Uri.base.queryParameters;
    final tab = int.tryParse(q['tab'] ?? '');
    if (tab != null && tab >= 0 && tab < AppTab.values.length) ref.read(tabProvider.notifier).state = AppTab.values[tab];
    final s = Scenario.values.where((s) => s.name == q['scenario']).firstOrNull;
    if (s != null) ref.read(scenarioProvider.notifier).state = s;
    final drop = MockDrop.values.where((d) => d.name == q['drop']).firstOrNull;
    if (drop != null) {
      final repo = ref.read(repositoryProvider);
      if (repo is MockRepository) repo.nextDrop = drop;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) Routes.drop(context);
      });
    }
    final source = DataSource.values.where((d) => d.name == q['source']).firstOrNull;
    if (source != null) ref.read(dataSourceProvider.notifier).state = source;
    if (q['checkin'] == '1') ref.read(gameProvider.notifier).checkIn();
    final item = ref.read(repositoryProvider).food(q['item'] ?? '');
    if (item != null) ref.read(logIntentProvider.notifier).state = item;
    final loam = int.tryParse(q['loam'] ?? '');
    if (loam != null) ref.read(gameProvider.notifier).debugGrantLoam(loam);
    if (q['greenhouse'] == '1') {
      Routes.greenhouse(context);
      final pulls = int.tryParse(q['pull'] ?? '');
      if (pulls != null) {
        Future.delayed(const Duration(milliseconds: 700), () {
          final out = ref.read(gameProvider.notifier).pull(pulls, fromPackets: false);
          if (out != null && mounted) showPullReveal(context, out);
        });
      }
    }
    BinWorld.debugHour = double.tryParse(q['hour'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(recoveredPhotoProvider, (_, next) {
      if (next.hasError) showToast(ref, 'Could not recover the interrupted photo. Choose it again from Log.');
      final bytes = next.valueOrNull;
      if (bytes != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Routes.photo(context, recovered: bytes);
        });
      }
    });
    final tab = ref.watch(tabProvider);

    // Opening Layers counts as checking on the bin.
    ref.listen(tabProvider, (prev, next) {
      if (next == AppTab.layers) {
        ref.read(gameProvider.notifier).checkInAsync();
      }
    });

    ref.listen(binProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      if (!ref.read(repositoryProvider).serverGame) ref.read(gameProvider.notifier).syncHealthyHours(s.healthyHoursToday);
      final ready = s.bottomMeasured && !s.readingsStale && s.bottomStage == Stage.ready;
      if (ready && !_readyNotified) Notifications.compostReady();
      _readyNotified = ready;
    });

    return Scaffold(
      backgroundColor: C.paper,
      body: Stack(
        children: [
          const Positioned.fill(child: TopoBackdrop()),
          IndexedStack(index: tab.index, children: const [HomeScreen(), LayersScreen(), LogScreen(), SocialScreen(), ProfileScreen()]),
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
