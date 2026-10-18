import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/reward_reveal.dart';
import '../../domain/models.dart';
import '../../state/game.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Rewards inbox (from the gift on Home): what's waiting to open, then a
/// quiet history of what you've earned.
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key, required this.openGreenhouse});

  /// Seed Packets open in the Greenhouse (passed in so features stay apart).
  final Future<void> Function(BuildContext) openGreenhouse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    final waiting = g.crates.length + g.packets;
    final parts = [
      if (g.crates.isNotEmpty) '${g.crates.length} crate${g.crates.length == 1 ? '' : 's'}',
      if (g.packets > 0) '${g.packets} Seed Packet${g.packets == 1 ? '' : 's'}',
    ];

    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Rewards',
        subtitle: waiting == 0 ? 'All opened' : parts.join(' · '),
        trailing: Pressable(
          onTap: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.all(S.x1),
            child: Icon(PhosphorIconsBold.x, color: C.onBrand, size: 22),
          ),
        ),
        hero: Align(
          alignment: Alignment.centerLeft,
          child: Text(waiting == 0 ? 'Nothing to open' : '$waiting to open', style: T.display.copyWith(color: C.onBrand)),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: S.x5),
                const SectionLabel('WAITING'),
                const SizedBox(height: S.x2),
                if (waiting == 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x3),
                    child: Text('Fill the daily goal and earn achievements to get crates.', style: T.body),
                  ),
                for (final (i, tier) in g.crates.indexed) ...[
                  if (i > 0) const Hairline(),
                  _Row(
                    icon: PhosphorIconsFill.package,
                    tint: _crateTint(tier),
                    title: crateLabel(tier),
                    subtitle: 'From ${i < g.crateFrom.length ? g.crateFrom[i] : 'a reward'}',
                    action: PillButton(
                      label: 'Open',
                      dense: true,
                      onTap: () async {
                        final o = await ref.read(gameProvider.notifier).openCrateAsync(i);
                        if (o != null && context.mounted) await revealCrate(context, o.tier, o.loam, o.packets);
                      },
                    ),
                  ),
                ],
                if (g.packets > 0) ...[
                  if (g.crates.isNotEmpty) const Hairline(),
                  _Row(
                    icon: PhosphorIconsFill.plant,
                    tint: (C.pinkSoft, C.pinkDeep),
                    title: '${g.packets} Seed Packet${g.packets == 1 ? '' : 's'}',
                    subtitle: 'Opens in the Greenhouse',
                    action: PillButton(
                      label: 'Greenhouse',
                      dense: true,
                      color: C.surface,
                      textColor: C.forest,
                      onTap: () => openGreenhouse(context),
                    ),
                  ),
                ],
                const SectionBreak(),
                const SectionLabel('HISTORY'),
                const SizedBox(height: S.x2),
                if (g.rewardLog.isEmpty) Text('Rewards you open will show up here.', style: T.body),
                for (final (i, e) in g.rewardLog.indexed) ...[
                  if (i > 0) const Hairline(),
                  _HistoryRow(e),
                ],
              ],
            ),
          ),
        ].animate(interval: M.stagger).fadeIn(duration: 300.ms, curve: M.ease),
      ),
    );
  }

  static (Color, Color) _crateTint(CrateTier t) => switch (t) {
    CrateTier.sprout => (C.leafSoft, C.leaf),
    CrateTier.grove => (C.amberSoft, C.amber),
    CrateTier.canopy => (C.waterSoft, C.water),
  };
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.tint, required this.title, required this.subtitle, required this.action});
  final IconData icon;
  final (Color, Color) tint;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: tint.$1, borderRadius: BorderRadius.circular(R.chip)),
            child: Icon(icon, size: 20, color: tint.$2),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.heading.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600)),
                Text(subtitle, style: T.small),
              ],
            ),
          ),
          const SizedBox(width: S.x2),
          action,
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.e);
  final RewardEvent e;

  @override
  Widget build(BuildContext context) {
    final icon = switch (e.kind) {
      RewardKind.crateOpened => PhosphorIconsRegular.package,
      RewardKind.packetsOpened => PhosphorIconsRegular.plant,
      RewardKind.streak => PhosphorIconsRegular.flame,
      RewardKind.levelUp => PhosphorIconsRegular.arrowCircleUp,
      RewardKind.harvest => PhosphorIconsRegular.basket,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: e.kind == RewardKind.streak ? C.pinkDeep : C.muted),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: T.body.copyWith(color: C.ink)),
                Text(e.detail, style: T.small),
              ],
            ),
          ),
          Text(whenLabel(e.time), style: T.small),
        ],
      ),
    );
  }
}

/// "Now", "3h ago", "Mon".
String whenLabel(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return 'Now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
  return '${t.day}/${t.month}';
}
