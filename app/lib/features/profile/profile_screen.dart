import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/reward_reveal.dart';
import '../../app/routes.dart';
import '../../data/collectibles.dart';
import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../state/social.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

String crateName(CrateTier t) => switch (t) {
  CrateTier.sprout => 'Sprout crate',
  CrateTier.grove => 'Grove crate',
  CrateTier.canopy => 'Canopy crate',
};

/// Level, stats, rewards waiting, impact, achievements, collection, settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    final level = g.level;
    final from = xpForLevel(level);
    final to = xpForLevel(level + 1);

    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, style: T.value.copyWith(color: C.onBrand, fontSize: 20)),
          const SizedBox(height: 2),
          Text(label, style: T.small.copyWith(color: C.onBrandMuted, fontSize: 11.5)),
        ],
      ),
    );
    Widget vline() => Container(width: 1, height: 30, color: C.onBrand.withValues(alpha: 0.25));

    return BrandPage(
      title: 'You',
      subtitle: 'Level $level · ${g.displayTitle}',
      trailing: const Avatar('You', size: 56, onBrand: true),
      hero: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ThinBar(value: (g.totalXp - from) / (to - from), color: C.onBrand, track: C.onBrand.withValues(alpha: 0.25), height: 6),
              ),
              const SizedBox(width: S.x3),
              Text('${g.totalXp - from} / ${to - from} XP', style: T.num.copyWith(color: C.onBrand, fontSize: 12)),
            ],
          ),
          const SizedBox(height: S.x5),
          Row(
            children: [
              stat('${g.streak.days}', 'day streak'),
              vline(),
              stat('${g.totalXp}', 'total XP'),
              vline(),
              stat('${g.harvests}', 'harvests'),
              vline(),
              stat('${g.loam}', 'Loam'),
            ],
          ),
        ],
      ),
      children: [
        if (ref.watch(socialSessionProvider).valueOrNull case final account?) ...[
          PillButton(label: 'My shared progress', onTap: () => Routes.socialProfile(context, account.userId)),
          const SizedBox(height: S.x3),
          Text('Care progress and private leaderboards live in Social. The rewards below are your local demo garden.', style: T.small),
          const SectionBreak(),
        ],
        _Rewards(g: g),
        const SectionBreak(),
        _Impact(g: g),
        const SectionBreak(),
        SectionLabel('ACHIEVEMENTS', trailing: Text('Every tier pays a crate', style: T.small.copyWith(fontSize: 11))),
        const SizedBox(height: S.x2),
        for (final (i, a) in g.achievements.indexed) ...[if (i > 0) const Hairline(), _AchievementRow(a)],
        const SectionBreak(),
        const SectionLabel('COLLECTION'),
        const SizedBox(height: S.x3),
        Row(
          children: [
            Text('${g.collected}', style: T.stat.copyWith(fontSize: 30)),
            Text(' / ${collectibles.length} collectibles', style: T.label.copyWith(color: C.ink2)),
            const Spacer(),
            Pressable(
              onTap: () => Routes.greenhouse(context),
              child: Row(
                children: [
                  Text('Greenhouse', style: T.button.copyWith(color: C.forest)),
                  const SizedBox(width: 4),
                  const Icon(PhosphorIconsBold.arrowRight, size: 14, color: C.forest),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x3),
        _RarityStrip(owned: g.owned),
        const SectionBreak(),
        const SectionLabel('SETTINGS'),
        const SizedBox(height: S.x2),
        const _SettingRow(PhosphorIconsRegular.trash, 'Kitchen bin', 'Connected · ESP32'),
        const Hairline(),
        const _SettingRow(PhosphorIconsRegular.bell, 'Notifications', 'Compost ready, streak at risk'),
        const Hairline(),
        const _SettingRow(PhosphorIconsRegular.info, 'About Calmpost', 'Hack the Valley 11'),
      ].animate(interval: M.stagger).fadeIn(duration: 360.ms, curve: M.ease),
    );
  }
}

class _Rewards extends ConsumerWidget {
  const _Rewards({required this.g});
  final GameState g;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = g.crates.length + g.packets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('REWARDS WAITING', trailing: waiting > 0 ? PinkPill('$waiting new') : null),
        const SizedBox(height: S.x3),
        Row(
          children: [
            for (final c in g.crates) ...[_RewardMark(icon: PhosphorIconsFill.package, label: crateName(c).split(' ').first), const SizedBox(width: S.x4)],
            for (var i = 0; i < g.packets; i++) ...[const _RewardMark(icon: PhosphorIconsFill.plant, label: 'Packet'), const SizedBox(width: S.x4)],
            const Spacer(),
            PillButton(
              label: 'Open',
              dense: true,
              onTap: g.crates.isEmpty
                  ? () => Routes.greenhouse(context)
                  : () async {
                      final o = ref.read(gameProvider.notifier).openCrate(0);
                      if (o != null) await revealCrate(context, o.tier, o.loam, o.packets);
                    },
            ),
          ],
        ),
      ],
    );
  }
}

class _RewardMark extends StatelessWidget {
  const _RewardMark({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: C.surface,
            shape: BoxShape.circle,
            border: Border.all(color: C.pink, width: 1.5),
          ),
          child: Icon(icon, size: 22, color: C.pinkDeep),
        ),
        const SizedBox(height: 4),
        Text(label, style: T.small.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _Impact extends StatelessWidget {
  const _Impact({required this.g});
  final GameState g;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: T.stat),
          const SizedBox(height: 2),
          Text(label, style: T.small),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('YOUR IMPACT'),
        const SizedBox(height: S.x3),
        IntrinsicHeight(
          child: Row(
            children: [
              stat('${g.kgDiverted.toStringAsFixed(1)} kg', 'kept from landfill'),
              const Hairline(vertical: true),
              const SizedBox(width: S.x4),
              stat('${g.co2eAvoided.toStringAsFixed(1)} kg', 'CO₂e avoided'),
              const Hairline(vertical: true),
              const SizedBox(width: S.x4),
              stat('\$${g.dollarsSaved.toStringAsFixed(0)}', 'fertilizer saved'),
            ],
          ),
        ),
        const SizedBox(height: S.x2),
        Text('Estimates from what you\'ve logged.', style: T.small.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow(this.a);
  final Achievement a;

  @override
  Widget build(BuildContext context) {
    final done = a.tier > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: done ? C.forest : C.surface,
              shape: BoxShape.circle,
              border: done ? null : Border.all(color: C.line),
            ),
            child: Icon(a.icon, size: 20, color: done ? C.onForest : C.faint),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(a.title, style: T.heading.copyWith(fontSize: 15))),
                    for (var i = 0; i < a.goals.length; i++)
                      Container(
                        margin: const EdgeInsets.only(left: 3),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: i < a.tier ? C.pink : C.line, shape: BoxShape.circle),
                      ),
                  ],
                ),
                Text(a.description, style: T.small),
                const SizedBox(height: S.x2),
                Row(
                  children: [
                    Expanded(
                      child: ThinBar(value: a.maxed ? 1 : a.progress / a.nextGoal, color: C.forest),
                    ),
                    const SizedBox(width: S.x2),
                    Text(a.maxed ? 'Done' : '${_fmt(a.progress)} / ${_fmt(a.nextGoal)}', style: T.small.copyWith(fontSize: 11.5)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(PhosphorIconsRegular.package, size: 13, color: C.pinkDeep),
                    const SizedBox(width: 4),
                    Text(a.maxed ? 'All crates earned' : 'Next: ${crateName(a.nextReward)}', style: T.small.copyWith(fontSize: 11.5, color: C.ink2)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// Collected count per rarity as a small strip of dots.
class _RarityStrip extends StatelessWidget {
  const _RarityStrip({required this.owned});
  final Map<String, int> owned;

  Map<Rarity, (int, int)> get _counts => {
    for (final r in Rarity.values)
      r: (collectibles.where((c) => c.rarity == r && (owned[c.id] ?? 0) > 0).length, collectibles.where((c) => c.rarity == r).length),
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final e in _counts.entries)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 4,
                  margin: const EdgeInsets.only(right: 6),
                  color: rarityColor(e.key).withValues(alpha: e.value.$1 > 0 ? 1 : 0.3),
                ),
                const SizedBox(height: 4),
                Text('${e.value.$1}/${e.value.$2}', style: T.num.copyWith(fontSize: 11.5)),
                Text(e.key.name[0].toUpperCase() + e.key.name.substring(1), style: T.small.copyWith(fontSize: 10.5)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow(this.icon, this.title, this.sub);
  final IconData icon;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          Icon(icon, size: 20, color: C.ink2),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.heading.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600)),
                Text(sub, style: T.small),
              ],
            ),
          ),
          const Icon(PhosphorIconsRegular.caretRight, size: 16, color: C.faint),
        ],
      ),
    );
  }
}
