import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/stats_bar.dart';
import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../state/celebrations.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';

const avatarTones = [Tone.leaf, Tone.sky, Tone.flame, Tone.moss, Tone.coral, Tone.sun];

class LeaguesScreen extends ConsumerStatefulWidget {
  const LeaguesScreen({super.key});

  @override
  ConsumerState<LeaguesScreen> createState() => _LeaguesScreenState();
}

class _LeaguesScreenState extends ConsumerState<LeaguesScreen> {
  bool _friends = false;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(standingsProvider);
    final now = DateTime.now();
    final reset = DateTime(now.year, now.month, now.day + (8 - now.weekday));
    final left = reset.difference(now);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          StatsBar(leading: Text('Leagues', style: T.h2)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x8),
              children: [
                _TierRow(current: st.tier.index),
                const SizedBox(height: S.x4),
                Center(child: Text('${st.tier.name} League', style: T.h1)),
                const SizedBox(height: S.x1),
                Center(child: Text('Top $promoteCount move up to ${leagueTiers[st.tier.index + 1].name}', style: T.body)),
                const SizedBox(height: S.x2),
                Center(
                  child: Tag('${left.inDays}d ${left.inHours % 24}h left', tone: Tone.flame, icon: PhosphorIconsFill.clock, dense: true),
                ),
                const SizedBox(height: S.x4),
                _Toggle(friends: _friends, onChanged: (v) => setState(() => _friends = v)),
                const SizedBox(height: S.x4),
                if (_friends) const _FriendsTab() else _Weekly(st),
                const SizedBox(height: S.x4),
                Row(
                  children: [
                    const Icon(PhosphorIconsFill.info, size: 16, color: C.muted),
                    const SizedBox(width: S.x2),
                    Expanded(child: Text('League XP comes from care, not volume. A bigger bin doesn\'t win.', style: T.small)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < leagueTiers.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: i == current
                  ? LeagueBadge(i, size: 70)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(begin: const Offset(1, 1), end: const Offset(1.06, 1.06), duration: 1200.ms, curve: Curves.easeInOut)
                  : Opacity(
                      opacity: i < current ? 0.9 : 1,
                      child: LeagueBadge(i, size: 42, locked: i > current),
                    ),
            ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.friends, required this.onChanged});
  final bool friends;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool v) => Expanded(
      child: Pressable(
        onTap: () => onChanged(v),
        child: AnimatedContainer(
          duration: M.base,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: friends == v ? C.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(R.chip),
            border: Border.all(color: friends == v ? C.border : Colors.transparent, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(label, style: T.eyebrow.copyWith(color: friends == v ? C.ink : C.muted, fontSize: 12.5)),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.bgDeep, borderRadius: BorderRadius.circular(R.button)),
      child: Row(children: [seg('THIS WEEK', false), seg('FRIENDS', true)]),
    );
  }
}

class _Weekly extends StatelessWidget {
  const _Weekly(this.st);
  final Standing st;

  @override
  Widget build(BuildContext context) {
    final n = st.members.length;
    final rows = <Widget>[];
    for (var i = 0; i < n; i++) {
      final rank = i + 1;
      if (rank == promoteCount + 1) rows.add(const _ZoneDivider(promote: true));
      if (rank == n - demoteCount + 1) rows.add(const _ZoneDivider(promote: false));
      rows.add(
        _MemberRow(
          member: st.members[i],
          rank: rank,
          zone: zoneForRank(rank, n, tierIndex: st.tier.index),
        ),
      );
    }
    return Slab(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      child: Column(children: rows),
    );
  }
}

class _ZoneDivider extends StatelessWidget {
  const _ZoneDivider({required this.promote});
  final bool promote;

  @override
  Widget build(BuildContext context) {
    final color = promote ? C.leaf : C.coral;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
      child: Row(
        children: [
          Expanded(child: Container(height: 2, color: color.withValues(alpha: 0.35))),
          const SizedBox(width: S.x2),
          Icon(promote ? PhosphorIconsBold.caretDoubleUp : PhosphorIconsBold.caretDoubleDown, size: 14, color: color),
          const SizedBox(width: 4),
          Text(promote ? 'PROMOTION ZONE' : 'DEMOTION ZONE', style: T.eyebrow.copyWith(color: color, fontSize: 11)),
          const SizedBox(width: 4),
          Icon(promote ? PhosphorIconsBold.caretDoubleUp : PhosphorIconsBold.caretDoubleDown, size: 14, color: color),
          const SizedBox(width: S.x2),
          Expanded(child: Container(height: 2, color: color.withValues(alpha: 0.35))),
        ],
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.m, {super.key, this.size = 40});
  final LeagueMember m;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = m.isYou ? Tone.leaf : avatarTones[m.colorIndex % avatarTones.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.tint,
        shape: BoxShape.circle,
        border: Border.all(color: tone.face, width: 2),
      ),
      alignment: Alignment.center,
      child: m.isYou
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wren(mood: WrenMood.happy, size: size * 0.95),
            )
          : Text(
              m.initials,
              style: T.numM.copyWith(color: tone.lip, fontSize: size * 0.36),
            ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.rank, required this.zone});
  final LeagueMember member;
  final int rank;
  final LeagueZone zone;

  @override
  Widget build(BuildContext context) {
    final you = member.isYou;
    final rankColor = switch (zone) {
      LeagueZone.promote => C.leaf,
      LeagueZone.demote => C.coral,
      LeagueZone.safe => C.muted,
    };
    final medal = switch (rank) {
      1 => C.sun,
      2 => const Color(0xFFC9CED6),
      3 => const Color(0xFFDDA06A),
      _ => null,
    };
    final row = AnimatedContainer(
      duration: M.slow,
      margin: const EdgeInsets.symmetric(horizontal: S.x2),
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
      decoration: BoxDecoration(
        color: you ? C.skyTint : Colors.transparent,
        borderRadius: BorderRadius.circular(R.button),
        border: Border.all(color: you ? C.sky.withValues(alpha: 0.5) : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: medal != null
                ? Icon(PhosphorIconsFill.medal, color: medal, size: 26)
                : Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: T.numM.copyWith(color: rankColor),
                  ),
          ),
          const SizedBox(width: S.x2),
          Avatar(member),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  you ? 'You' : member.name,
                  style: T.bodyStrong.copyWith(color: you ? C.skyLip : C.ink),
                  overflow: TextOverflow.ellipsis,
                ),
                if (member.streak > 0)
                  Row(
                    children: [
                      const Flame(size: 12),
                      const SizedBox(width: 3),
                      Text('${member.streak}', style: T.small.copyWith(fontSize: 11.5, color: C.flame)),
                    ],
                  ),
              ],
            ),
          ),
          if (you)
            CountUp(
              member.xp,
              suffix: ' XP',
              style: T.numM.copyWith(fontSize: 15, color: C.skyLip),
            )
          else
            Text('${member.xp} XP', style: T.numM.copyWith(fontSize: 15, color: C.inkSoft)),
        ],
      ),
    );
    return you ? row.animate(key: ValueKey(member.xp)).shimmer(duration: 900.ms, color: Colors.white.withValues(alpha: 0.6)) : row;
  }
}

class _FriendsTab extends ConsumerWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(standingsProvider);
    final progress = ref.watch(gameProvider.select((g) => g.friendQuestProgress));
    final friends = st.members.where((m) => m.isFriend || m.isYou).toList();
    final priya = friends.firstWhere((m) => m.name.startsWith('Priya'), orElse: () => friends.first);
    const goal = 10;

    return Column(
      children: [
        Slab(
          color: C.mossTint,
          edge: C.moss.withValues(alpha: 0.4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 40,
                    child: Stack(
                      children: [
                        Positioned(left: 0, child: Avatar(priya)),
                        Positioned(left: 24, child: Avatar(st.members.firstWhere((m) => m.isYou))),
                      ],
                    ),
                  ),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FRIEND QUEST', style: T.eyebrow.copyWith(color: C.mossLip)),
                        const SizedBox(height: 2),
                        Text('Follow 10 of Wren\'s tips together', style: T.title),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              Row(
                children: [
                  Expanded(
                    child: ProgressBar(value: progress / goal, color: C.moss, label: '$progress / $goal'),
                  ),
                  const SizedBox(width: S.x3),
                  Chest(size: 40, dim: progress < goal),
                ],
              ),
              const SizedBox(height: S.x2),
              Text('Ends Sunday. You and Priya both get 50 acorns.', style: T.small),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        Slab(
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          child: Column(
            children: [
              for (final (i, m) in friends.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text('${i + 1}', style: T.numM.copyWith(color: C.muted)),
                      ),
                      Avatar(m),
                      const SizedBox(width: S.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.isYou ? 'You' : m.name, style: T.bodyStrong),
                            Text('${m.xp} XP this week', style: T.small.copyWith(fontSize: 12)),
                          ],
                        ),
                      ),
                      if (!m.isYou)
                        ChunkyButton(
                          label: 'Nudge',
                          variant: ChunkyVariant.white,
                          expand: false,
                          height: 36,
                          radius: R.chip,
                          onPressed: () => ref.read(toastProvider.notifier).show('Wren waved at ${m.name.split(' ').first}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
