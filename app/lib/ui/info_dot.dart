import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'components.dart';
import 'tokens.dart';
import 'type.dart';

/// The app's few "what does this mean?" hints. Keep this list short: a dot
/// only goes where a first-time user couldn't work the answer out alone.
enum InfoTip {
  score(
    'Your health score',
    'It blends moisture (weighted most, it\'s our most reliable sensor), temperature, CO₂ and your greens-to-browns balance. '
        'It\'s a guide from the sensors, not a lab test.',
  ),
  xp(
    'How you earn XP',
    'Confirmed compostable additions earn 1 XP per 20 g, with bonuses for following advice and other care. '
        'Volume and action rewards share a 60 XP daily cap. Keep-out materials earn no volume XP.',
  ),
  whatToAdd(
    'Where this comes from',
    'These suggestions are based on your bin\'s live readings right now. Follow one for +15 XP. '
        'If everything\'s in range, the best move is to add nothing.',
  ),
  chart(
    'Reading the chart',
    'Moisture charts shade the app’s 40–60 guide on the probe’s relative scale, not water by weight. '
        'Dashed pink lines mark additions; timing alone does not prove an addition caused a change. '
        'Choose a probe to see its own history. Temperature and CO₂ have no shaded target band.',
  ),
  verdict(
    'Why this answer',
    'The verdict is checked against your bin\'s readings right now. '
        'The same scrap can get a different answer tomorrow if the bin is wetter or drier.',
  ),
  league(
    'How the league works',
    'You\'re racing 29 others on XP earned this week. The top 7 move up a tier and the bottom 5 move down. '
        'It resets Sunday at 00:00 UTC.',
  ),
  impact('These are estimates', 'Worked out from what you\'ve logged and typical weights, not measured. They show the direction, not exact numbers.');

  const InfoTip(this.title, this.body);
  final String title;
  final String body;
}

/// Tips the user has opened this session. An unseen dot carries a small pink
/// marker; once read, it fades to `faint` so it stops asking for attention.
final seenTipsProvider = StateProvider<Set<InfoTip>>((ref) => const {});

/// A small "i" that opens a short explanation sheet. Use sparingly: one per
/// section at most.
class InfoDot extends ConsumerWidget {
  const InfoDot(this.tip, {super.key, this.onBrand = false});
  final InfoTip tip;

  /// White variant for the green brand band.
  final bool onBrand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(seenTipsProvider).contains(tip);
    final color = onBrand ? C.onBrandMuted : (seen ? C.faint : C.muted);
    return Semantics(
      button: true,
      label: 'About: ${tip.title}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          showInfoSheet(context, tip);
          ref.read(seenTipsProvider.notifier).update((s) => {...s, tip});
        },
        // 32px tap area around a 16px icon.
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(PhosphorIconsRegular.info, size: 16, color: color),
              if (!seen)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(color: C.pink, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showInfoSheet(BuildContext context, InfoTip tip) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.hero))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x6, S.gutter, S.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tip.title, style: T.title),
            const SizedBox(height: S.x2),
            Text(tip.body, style: T.body),
            const SizedBox(height: S.x5),
            PillButton(label: 'Got it', onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    ),
  );
}
