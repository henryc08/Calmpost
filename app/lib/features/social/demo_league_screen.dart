import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/toast.dart';
import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/info_dot.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Weekly league, friends and co-op quests.
class DemoLeagueScreen extends ConsumerStatefulWidget {
  const DemoLeagueScreen({super.key});

  @override
  ConsumerState<DemoLeagueScreen> createState() => _DemoLeagueScreenState();
}

enum _View { league, friends }

class _DemoLeagueScreenState extends ConsumerState<DemoLeagueScreen> {
  _View _view = _View.league;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(standingsProvider);
    final me = st.members.firstWhere((m) => m.isYou);
    final now = DateTime.now().toUtc();
    final reset = DateTime.utc(now.year, now.month, now.day + (7 - now.weekday % 7));
    final left = reset.difference(now);
    final next =
        leagueTiers[(st.tier.index + 1).clamp(0, leagueTiers.length - 1)];
    final toPromo = st.yourRank <= promoteCount
        ? 0
        : st.promotionCutoffXp - me.xp + 1;

    return BrandPage(
      title: '${st.tier.name} League',
      subtitle:
          'Top $promoteCount move up to ${next.name} · ${left.inDays}d ${left.inHours % 24}h left',
      hero: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '#${st.yourRank}',
                style: T.hero.copyWith(fontSize: 68, color: C.onBrand),
              ),
              const SizedBox(width: S.x4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CountUp(me.xp, style: T.value.copyWith(color: C.onBrand)),
                      Text(
                        'XP this week',
                        style: T.small.copyWith(color: C.onBrandMuted),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: toPromo == 0 ? C.pink : C.onBrand,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(
                    toPromo == 0 ? 'PROMOTION ZONE' : '$toPromo XP TO GO',
                    style: T.caps.copyWith(
                      fontSize: 10.5,
                      color: toPromo == 0 ? C.ink : C.brandDeep,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x4),
          _Ladder(current: st.tier.index),
        ],
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: PaperSegments<_View>(
                values: _View.values,
                selected: _view,
                label: (v) => v == _View.league ? 'This week' : 'Friends',
                onChanged: (v) => setState(() => _view = v),
              ),
            ),
            const InfoDot(InfoTip.league),
          ],
        ),
        const SizedBox(height: S.x4),
        if (_view == _View.league) ..._league(st) else ..._friends(st),
        const SizedBox(height: S.x4),
        Text(
          'League XP only comes from care, so a bigger bin can\'t win.',
          style: T.small,
        ),
      ].animate(interval: 25.ms).fadeIn(duration: 300.ms, curve: M.ease),
    );
  }

  List<Widget> _league(Standing st) {
    final n = st.members.length;
    final out = <Widget>[];
    for (var i = 0; i < n; i++) {
      final rank = i + 1;
      if (rank == promoteCount + 1) out.add(const _ZoneDivider(promote: true));
      // Only when the zones don't overlap (small leagues have no demotion zone).
      if (rank == n - demoteCount + 1 && rank > promoteCount + 1) {
        out.add(const _ZoneDivider(promote: false));
      }
      out.add(
        _MemberRow(
          member: st.members[i],
          rank: rank,
          zone: zoneForRank(rank, n, tierIndex: st.tier.index),
        ),
      );
    }
    return out;
  }

  List<Widget> _friends(Standing st) {
    final progress = ref.watch(
      gameProvider.select((g) => g.friendQuestProgress),
    );
    final friends = st.members.where((m) => m.isFriend || m.isYou).toList();
    final buddy = friends.firstWhere(
      (m) => !m.isYou,
      orElse: () => friends.first,
    );
    const goal = 10;
    return [
      const SectionLabel('FRIEND QUEST', trailing: PinkPill('50 Loam each')),
      const SizedBox(height: S.x3),
      Text('Follow 10 next best actions together', style: T.title),
      const SizedBox(height: S.x3),
      Row(
        children: [
          SizedBox(
            width: 58,
            height: 36,
            child: Stack(
              children: [
                Avatar(buddy.name),
                const Positioned(
                  left: 22,
                  child: Avatar('You', highlight: true),
                ),
              ],
            ),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: ThinBar(value: progress / goal, color: C.pink, height: 6),
          ),
          const SizedBox(width: S.x3),
          Text('$progress / $goal', style: T.num),
        ],
      ),
      const SizedBox(height: S.x2),
      Text('With ${buddy.name.split(' ').first} · ends Sunday', style: T.small),
      const SectionBreak(),
      const SectionLabel('FRIENDS'),
      const SizedBox(height: S.x2),
      for (final (i, m) in friends.indexed) ...[
        if (i > 0) const Hairline(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Row(
            children: [
              Avatar(m.isYou ? 'You' : m.name, highlight: m.isYou),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.isYou ? 'You' : m.name,
                      style: T.heading.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${m.xp} XP this week · ${m.streak}-day streak',
                      style: T.small,
                    ),
                  ],
                ),
              ),
              if (!m.isYou)
                Pressable(
                  onTap: () =>
                      showToast(ref, 'Nudged ${m.name.split(' ').first}'),
                  child: Padding(
                    padding: const EdgeInsets.all(S.x2),
                    child: Text(
                      'Nudge',
                      style: T.button.copyWith(color: C.forest, fontSize: 13.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }
}

/// Six tiers as a row of circles: done, current (larger), locked.
class _Ladder extends StatelessWidget {
  const _Ladder({required this.current});
  final int current;

  static const _icons = [
    PhosphorIconsFill.acorn,
    PhosphorIconsFill.plant,
    PhosphorIconsFill.leaf,
    PhosphorIconsFill.flower,
    PhosphorIconsFill.tree,
    PhosphorIconsFill.treeEvergreen,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < leagueTiers.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= current
                    ? C.onBrand
                    : C.onBrand.withValues(alpha: 0.25),
              ),
            ),
          Column(
            children: [
              Container(
                width: i == current ? 40 : 28,
                height: i == current ? 40 : 28,
                decoration: BoxDecoration(
                  color: i <= current ? C.onBrand : Colors.transparent,
                  shape: BoxShape.circle,
                  border: i > current
                      ? Border.all(
                          color: C.onBrand.withValues(alpha: 0.45),
                          width: 1.5,
                        )
                      : null,
                ),
                child: Icon(
                  i > current ? PhosphorIconsFill.lock : _icons[i],
                  size: i == current ? 20 : 13,
                  color: i > current
                      ? C.onBrand.withValues(alpha: 0.6)
                      : (i == current ? C.brandDeep : C.brand),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ZoneDivider extends StatelessWidget {
  const _ZoneDivider({required this.promote});
  final bool promote;

  @override
  Widget build(BuildContext context) {
    final color = promote ? C.leaf : C.clay;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 1, color: color.withValues(alpha: 0.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x2),
            child: Text(
              promote ? 'PROMOTION ZONE' : 'DEMOTION ZONE',
              style: T.caps.copyWith(color: color, fontSize: 10),
            ),
          ),
          Expanded(
            child: Container(height: 1, color: color.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.rank,
    required this.zone,
  });
  final LeagueMember member;
  final int rank;
  final LeagueZone zone;

  @override
  Widget build(BuildContext context) {
    final you = member.isYou;
    final rankColor = switch (zone) {
      LeagueZone.promote => C.leaf,
      LeagueZone.demote => C.clay,
      LeagueZone.safe => C.muted,
    };
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: you ? C.pink : Colors.transparent, width: 3),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(S.x2, 9, 0, 9),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: T.num.copyWith(color: rankColor, fontSize: 14),
            ),
          ),
          Avatar(you ? 'You' : member.name, size: 32, highlight: you),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(
              you ? 'You' : member.name,
              overflow: TextOverflow.ellipsis,
              style: T.heading.copyWith(
                fontSize: 14.5,
                fontWeight: you ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (member.streak > 0) ...[
            const Icon(PhosphorIconsFill.fire, size: 13, color: C.pink),
            const SizedBox(width: 2),
            Text('${member.streak}', style: T.small.copyWith(fontSize: 11.5)),
            const SizedBox(width: S.x4),
          ],
          SizedBox(
            width: 62,
            child: Text(
              '${member.xp} XP',
              textAlign: TextAlign.right,
              style: T.num.copyWith(
                fontSize: 13.5,
                color: you ? C.ink : C.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
