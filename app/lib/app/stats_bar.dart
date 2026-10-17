import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../state/game.dart';
import '../state/providers.dart';
import '../ui/ui.dart';
import 'routes.dart';

/// Top bar shown on every main tab: health, streak, acorns.
class StatsBar extends ConsumerWidget {
  const StatsBar({super.key, this.leading});
  final Widget? leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final streak = ref.watch(gameProvider.select((g) => g.streak));
    final acorns = ref.watch(gameProvider.select((g) => g.acorns));
    final lit = streak.caredOn(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.x2, S.x2),
      child: Row(
        children: [
          Expanded(child: leading ?? const SizedBox()),
          _Pill(
            onTap: () => Routes.health(context),
            icon: Icon(PhosphorIconsFill.heartbeat, color: _healthColor(health?.score), size: 22),
            child: CountUp(health?.score ?? 0, style: T.numM.copyWith(color: _healthColor(health?.score))),
          ),
          _Pill(
            onTap: () => Routes.streak(context),
            icon: Flame(size: 22, lit: lit),
            child: CountUp(streak.days, style: T.numM.copyWith(color: lit ? C.flame : C.faint)),
          ),
          _Pill(
            onTap: () => Routes.shop(context),
            icon: const AcornIcon(size: 22),
            child: CountUp(acorns, style: T.numM.copyWith(color: const Color(0xFFB06A2C))),
          ),
        ],
      ),
    );
  }
}

Color _healthColor(int? score) {
  if (score == null) return C.faint;
  if (score >= 70) return C.leaf;
  if (score >= 50) return C.sunLip;
  return C.coral;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.child, required this.onTap});
  final Widget icon;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(width: 5), child]),
      ),
    );
  }
}
