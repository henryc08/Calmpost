import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/seed_lessons.dart';
import '../../domain/progression.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

class SeedLearning extends StatelessWidget {
  const SeedLearning({super.key, required this.id, this.onDark = false});
  final String id;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final lesson = lessonForSeed(id);
    final ink = onDark ? C.onBrand : C.ink;
    final muted = onDark ? C.onBrandMuted : C.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(buffLabel(seedBuffs[id]!), style: T.heading.copyWith(color: onDark ? C.pink : C.forest)),
        const SizedBox(height: S.x2),
        Text(buffDetail(seedBuffs[id]!), style: T.small.copyWith(color: muted)),
        const SizedBox(height: S.x5),
        Text('FIELD NOTE · ${lesson.title}', style: T.label.copyWith(color: ink)),
        const SizedBox(height: S.x2),
        Text(lesson.fact, style: T.body.copyWith(color: ink)),
        const SizedBox(height: S.x2),
        Text('Try this: ${lesson.action}', style: T.small.copyWith(color: muted)),
        const SizedBox(height: S.x3),
        Text(
          fantasySeeds.contains(id)
              ? 'Imaginary plant, real environmental lesson. Buffs affect the game only.'
              : 'This is a general environmental lesson. Buffs affect the game, not real plants or bin health.',
          style: T.small.copyWith(color: muted, fontSize: 11),
        ),
        const SizedBox(height: S.x2),
        Text('Source: US EPA · Composting at Home', style: T.small.copyWith(color: muted)),
        const SizedBox(height: S.x2),
        PillButton(
          label: 'Copy source link',
          dense: true,
          color: onDark ? C.onBrand : C.sunk,
          textColor: C.ink,
          onTap: () async {
            await Clipboard.setData(const ClipboardData(text: SeedLesson.source));
          },
        ),
      ],
    );
  }
}
