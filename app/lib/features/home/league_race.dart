import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/xp_rules.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Your place in this week's league: the people just above and below you, and
/// how far it is to the promotion zone.
class LeagueRace extends ConsumerWidget {
  const LeagueRace({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(standingsProvider);
    final idx = st.yourRank - 1;
    final me = st.members[idx];
    final size = st.members.length < 3 ? st.members.length : 3;
    final from = (idx - 1).clamp(0, st.members.length - size);
    final window = st.members.sublist(from, from + size);
    final inZone = st.yourRank <= promoteCount;
    final toGo = inZone ? 0 : st.promotionCutoffXp - me.xp + 1;
    final now = DateTime.now();
    final left = DateTime(now.year, now.month, now.day + (8 - now.weekday)).difference(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          '${st.tier.name.toUpperCase()} LEAGUE · ${left.inDays}D ${left.inHours % 24}H LEFT',
          trailing: Pressable(
            onTap: onOpen,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Table',
                  style: T.small.copyWith(color: C.forest, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 3),
                const Icon(PhosphorIconsBold.arrowRight, size: 12, color: C.forest),
              ],
            ),
          ),
        ),
        const SizedBox(height: S.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('#${st.yourRank}', style: T.title.copyWith(fontSize: 34, height: 1)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(inZone ? 'In the promotion zone. Hold on until Sunday.' : '$toGo XP to the promotion zone', style: T.label.copyWith(color: C.ink2)),
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x3),
        ThinBar(value: inZone ? 1 : (st.promotionCutoffXp <= 0 ? 0.0 : me.xp / st.promotionCutoffXp).clamp(0, 1), color: C.pink, height: 6),
        const SizedBox(height: S.x3),
        for (final (i, m) in window.indexed)
          Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: m.isYou ? C.pink : Colors.transparent, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(S.x2, 7, 0, 7),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text('${from + i + 1}', style: T.num.copyWith(color: C.muted)),
                ),
                Avatar(m.isYou ? 'You' : m.name, size: 28, highlight: m.isYou),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(
                    m.isYou ? 'You' : m.name,
                    overflow: TextOverflow.ellipsis,
                    style: T.heading.copyWith(fontSize: 14, fontWeight: m.isYou ? FontWeight.w800 : FontWeight.w600),
                  ),
                ),
                Text('${m.xp} XP', style: T.num.copyWith(fontSize: 13, color: m.isYou ? C.ink : C.ink2)),
              ],
            ),
          ),
      ],
    );
  }
}
