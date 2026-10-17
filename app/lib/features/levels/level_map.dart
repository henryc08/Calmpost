import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/routes.dart';
import '../../app/toast.dart';
import '../../data/collectibles.dart';
import '../../domain/progression.dart';
import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

class LevelMapScreen extends ConsumerStatefulWidget {
  const LevelMapScreen({super.key});
  @override
  ConsumerState<LevelMapScreen> createState() => _LevelMapState();
}

class _LevelMapState extends ConsumerState<LevelMapScreen> {
  int? _claiming;
  int _chapter = 0;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(gameProvider);
    if (!_initialized) {
      final first = List.generate(g.level, (i) => i + 1).where((n) => !g.levelClaimed.contains(n)).firstOrNull ?? g.level;
      _chapter = (first - 1) ~/ 10;
      _initialized = true;
    }
    final maxed = g.level == maxLevel;
    final next = xpForLevel(g.level + 1);
    final from = xpForLevel(g.level);
    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Your growth trail',
        subtitle: '$xpPerLevel XP per level. A reward every step.',
        trailing: Semantics(
          label: 'Close level map',
          button: true,
          child: Pressable(
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(PhosphorIconsBold.x, color: C.onBrand),
            ),
          ),
        ),
        hero: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Level ${g.level}', style: T.title.copyWith(fontSize: 38, color: C.onBrand)),
            const SizedBox(height: S.x2),
            Text(
              maxed ? 'Trail complete. Your composting journey continues.' : '${next - g.totalXp} XP to level ${g.level + 1}',
              style: T.body.copyWith(color: C.onBrand),
            ),
            const SizedBox(height: S.x3),
            ThinBar(value: maxed ? 1 : (g.totalXp - from) / (next - from), color: C.pink, track: C.brandDeep, height: 8),
            const SizedBox(height: S.x3),
            Text('${g.totalXp} lifetime XP · ${g.levelRewardsReady} rewards ready', style: T.small.copyWith(color: C.onBrand)),
          ],
        ),
        children: [
          const SectionLabel('YOUR ACTIVE SEED'),
          const SizedBox(height: S.x3),
          Text(
            g.activeSeed == null
                ? 'Claim your starter, then activate a seed.'
                : '${collectibleById[g.activeSeed]!.name} · ${buffLabel(seedBuffs[g.activeSeed]!)}',
            style: T.heading,
          ),
          const SizedBox(height: S.x2),
          Text('One active seed. Small common perks grow into stronger, specialized buffs at higher rarities. Duplicates never stack.', style: T.small),
          const SizedBox(height: S.x3),
          PillButton(label: 'Visit Greenhouse', dense: true, onTap: () => Routes.greenhouse(context)),
          const SectionBreak(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 5; i++)
                PillButton(
                  label: '${i * 10 + 1}–${i * 10 + 10}',
                  dense: true,
                  color: _chapter == i ? C.forest : C.sunk,
                  textColor: _chapter == i ? C.onForest : C.ink,
                  onTap: () => setState(() => _chapter = i),
                ),
            ],
          ),
          const SizedBox(height: S.x5),
          for (var n = _chapter * 10 + 1; n <= (_chapter + 1) * 10; n++) _node(g, n),
          const SectionBreak(),
          Text('How you grow', style: T.heading),
          const SizedBox(height: S.x2),
          Text(
            'Confirmed compost earns 1 XP per 20 g. Care and quests add more. Action XP is capped at 60 per day, including seed buffs; quest XP is separate. Level rewards never award XP, so claiming cannot create an endless level-up loop.',
            style: T.small,
          ),
        ],
      ),
    );
  }

  Widget _node(GameState g, int level) {
    final reward = rewardForLevel(level);
    final claimed = g.levelClaimed.contains(level);
    final unlocked = g.level >= level;
    final color = claimed
        ? C.leaf
        : unlocked
        ? C.pink
        : C.line;
    final text = [
      '${reward.loam} Loam',
      if (reward.packets > 0) '${reward.packets} Seed Packet',
      if (reward.crate != null) '${reward.crate!.name} crate',
      if (reward.seed != null) '${collectibleById[reward.seed]!.name} seed',
    ].join(' · ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: unlocked ? color : C.faint),
                  ),
                  child: claimed ? const Icon(PhosphorIconsBold.check, color: C.onBrand, size: 20) : Text('$level', style: T.num.copyWith(color: C.ink)),
                ),
                Expanded(child: Container(width: 2, color: C.line)),
              ],
            ),
          ),
          const SizedBox(width: S.x4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: S.x6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LEVEL $level · ${xpForLevel(level)} XP', style: T.caps.copyWith(color: unlocked ? C.ink2 : C.muted)),
                  const SizedBox(height: S.x2),
                  Text(text, style: T.heading.copyWith(fontSize: 16)),
                  const SizedBox(height: S.x3),
                  if (claimed)
                    Text('Collected', style: T.small.copyWith(color: C.leaf))
                  else if (!unlocked)
                    Text('${xpForLevel(level) - g.totalXp} XP to unlock', style: T.small)
                  else
                    PillButton(
                      key: ValueKey('claim-level-$level'),
                      label: _claiming == level ? 'Saving…' : 'Claim level $level',
                      dense: true,
                      color: C.pink,
                      textColor: C.ink,
                      onTap: _claiming != null
                          ? null
                          : () async {
                              setState(() => _claiming = level);
                              final saved = await ref.read(gameProvider.notifier).claimLevelAsync(level);
                              if (!mounted) return;
                              setState(() => _claiming = null);
                              if (!saved) return;
                              showToast(ref, 'Level $level rewards collected');
                              if (reward.seed != null) await Routes.seed(context, reward.seed!);
                            },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
