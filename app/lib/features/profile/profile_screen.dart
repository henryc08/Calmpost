import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/routes.dart';
import '../../app/stats_bar.dart';
import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';
import 'garden.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    final st = ref.watch(standingsProvider);
    final level = g.level;
    final from = xpForLevel(level);
    final to = xpForLevel(level + 1);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          StatsBar(leading: Text('Profile', style: T.h2)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x8),
              children: [
                // Header
                Slab(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: const BoxDecoration(color: C.leafTint, shape: BoxShape.circle),
                            clipBehavior: Clip.antiAlias,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Wren(mood: WrenMood.happy, size: 96, hat: g.hat),
                            ),
                          ),
                          const SizedBox(width: S.x4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('LEVEL $level', style: T.eyebrow.copyWith(color: C.sunLip)),
                                const SizedBox(height: 2),
                                Text(titleForLevel(level), style: T.h2),
                                const SizedBox(height: S.x2),
                                ProgressBar(value: (g.totalXp - from) / (to - from), color: C.sun, label: '${g.totalXp - from} / ${to - from} XP'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: S.x4),
                      ChunkyButton(
                        label: 'Shop & wardrobe',
                        icon: PhosphorIconsFill.storefront,
                        variant: ChunkyVariant.white,
                        height: 46,
                        onPressed: () => Routes.shop(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: S.x5),
                Text('Statistics', style: T.h2),
                const SizedBox(height: S.x3),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        icon: Flame(size: 26, lit: g.caredToday),
                        value: '${g.streak.days}',
                        label: 'Day streak',
                      ),
                    ),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: _Stat(
                        icon: const Icon(PhosphorIconsFill.lightning, color: C.sun, size: 28),
                        value: '${g.totalXp}',
                        label: 'Total XP',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: S.x3),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(icon: LeagueBadge(st.tier.index, size: 26), value: st.tier.name, label: 'Current league'),
                    ),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: _Stat(
                        icon: const Icon(PhosphorIconsFill.basket, color: C.soil, size: 28),
                        value: '${g.harvests}',
                        label: 'Harvests',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: S.x5),
                _ImpactCard(g),
                const SizedBox(height: S.x5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: Text('My garden', style: T.h2)),
                    Text('${g.garden.where((p) => !p.wilted).length} plants', style: T.small),
                  ],
                ),
                const SizedBox(height: S.x1),
                Text('Every healthy day grows a plant. Neglect makes them wilt.', style: T.body),
                const SizedBox(height: S.x3),
                GardenField(plants: g.garden),
                const SizedBox(height: S.x5),
                Text('Achievements', style: T.h2),
                const SizedBox(height: S.x3),
                Slab(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
                  child: Column(
                    children: [
                      for (final (i, a) in g.achievements.indexed) ...[if (i > 0) const Divider(height: 1, thickness: 2, color: C.border), _AchievementRow(a)],
                    ],
                  ),
                ),
              ].animate(interval: M.stagger).fadeIn(duration: M.base).slideY(begin: 0.05),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final Widget icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Slab(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
      radius: R.button + 2,
      child: Row(
        children: [
          SizedBox(width: 30, child: Center(child: icon)),
          const SizedBox(width: S.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: T.numM.copyWith(fontSize: 19)),
                ),
                Text(label, style: T.small.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard(this.g);
  final GameState g;

  @override
  Widget build(BuildContext context) {
    final carKm = g.co2eAvoided / 0.17;
    Widget big(IconData icon, String value, String label) => Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: S.x1),
          FittedBox(
            child: Text(value, style: T.numL.copyWith(color: Colors.white, fontSize: 24)),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: T.small.copyWith(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5),
          ),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(color: C.leafLip, borderRadius: BorderRadius.circular(R.card)),
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(color: C.leaf, borderRadius: BorderRadius.circular(R.card)),
        padding: const EdgeInsets.all(S.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsFill.globeHemisphereWest, color: Colors.white, size: 22),
                const SizedBox(width: S.x2),
                Flexible(
                  child: Text('YOUR CLIMATE IMPACT', style: T.eyebrow.copyWith(color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: S.x4),
            Row(
              children: [
                big(PhosphorIconsFill.recycle, '${g.kgDiverted.toStringAsFixed(1)} kg', 'food kept out\nof landfill'),
                big(PhosphorIconsFill.cloud, '${g.co2eAvoided.toStringAsFixed(1)} kg', 'CO₂e methane\navoided'),
                big(PhosphorIconsFill.coins, '\$${g.dollarsSaved.toStringAsFixed(0)}', 'fertilizer\nyou didn\'t buy'),
              ],
            ),
            const SizedBox(height: S.x4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
              decoration: BoxDecoration(color: C.leafLip.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(R.chip)),
              child: Row(
                children: [
                  const Icon(PhosphorIconsFill.car, color: Colors.white, size: 18),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: Text(
                      'Like skipping ${carKm.round()} km of driving',
                      style: T.small.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.x2),
            Text(
              'Estimates: ${Impact.co2ePerKg} kg CO₂e per kg of food diverted from landfill.',
              style: T.small.copyWith(color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow(this.a);
  final Achievement a;

  @override
  Widget build(BuildContext context) {
    final tiers = [
      const Tone(Color(0xFFE2DBCD), Color(0xFFCFC6B4), C.bgDeep),
      const Tone(Color(0xFFDDA06A), Color(0xFFB97C47), C.soilTint),
      const Tone(Color(0xFFB9C2CC), Color(0xFF8F9AA6), C.skyTint),
      Tone.sun,
    ];
    final tone = tiers[a.tier];
    final maxed = a.tier >= a.goals.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 58,
                height: 62,
                decoration: BoxDecoration(color: tone.lip, borderRadius: BorderRadius.circular(R.button)),
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  decoration: BoxDecoration(color: tone.face, borderRadius: BorderRadius.circular(R.button)),
                  child: Icon(a.icon, color: a.tier == 0 ? const Color(0xFFB5AC9A) : Colors.white, size: 30),
                ),
              ),
              const SizedBox(height: 3),
              Text(a.tier == 0 ? 'LOCKED' : 'LEVEL ${a.tier}', style: T.eyebrow.copyWith(fontSize: 9.5, color: a.tier == 0 ? C.faint : tone.lip)),
            ],
          ),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title, style: T.title),
                const SizedBox(height: 2),
                Text(a.description, style: T.small),
                const SizedBox(height: S.x2),
                ProgressBar(
                  value: maxed ? 1 : a.progress / a.nextGoal,
                  color: C.sun,
                  height: 14,
                  label: maxed ? 'MAXED' : '${_fmt(a.progress)} / ${_fmt(a.nextGoal)}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
