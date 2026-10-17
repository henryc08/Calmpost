import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models.dart';
import '../../domain/xp_rules.dart';
import '../../ui/ui.dart';

/// "Wren is thinking…" while the advice call runs.
class ThinkingPanel extends StatelessWidget {
  const ThinkingPanel({super.key, required this.item});
  final FoodItem item;

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      color: C.surface,
      edge: C.border,
      child: Row(
        children: [
          IconBlob(item.icon, tone: Tone.sun, size: 52),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: T.title),
                const SizedBox(height: 2),
                Text('Wren is checking your bin…', style: T.body),
              ],
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: const BoxDecoration(color: C.leaf, shape: BoxShape.circle),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: 2, end: -4, delay: (i * 120).ms, duration: 320.ms, curve: Curves.easeInOut),
            ],
          ),
        ],
      ),
    );
  }
}

/// Duolingo's answer panel: tinted sheet that slides up with the verdict.
class VerdictPanel extends StatelessWidget {
  const VerdictPanel({
    super.key,
    required this.advice,
    required this.followsTip,
    required this.onAdd,
    required this.onKeepOut,
    required this.onPair,
    required this.onBack,
  });

  final Advice advice;
  final bool followsTip;
  final VoidCallback onAdd;
  final VoidCallback onKeepOut;
  final ValueChanged<FoodItem> onPair;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final (tone, icon, variant) = switch (advice.verdict) {
      Verdict.great => (Tone.leaf, PhosphorIconsBold.check, ChunkyVariant.primary),
      Verdict.careful => (Tone.sun, PhosphorIconsBold.exclamationMark, ChunkyVariant.sun),
      Verdict.avoid => (Tone.coral, PhosphorIconsBold.prohibit, ChunkyVariant.coral),
    };
    final avoid = advice.verdict == Verdict.avoid;
    final xpLine = avoid
        ? '+${Xp.avoidedBadAdd} XP for keeping it out'
        : followsTip
        ? '+${Xp.followedSuggestion} XP: this is one of Wren\'s tips'
        : 'Adding scraps earns no XP. Following Wren\'s tips does.';

    return _PanelShell(
      color: tone.tint,
      edge: tone.face.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: tone.face, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 26),
              ).animate().scale(begin: const Offset(0.2, 0.2), duration: 500.ms, curve: Curves.elasticOut),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(advice.headline, style: T.h2.copyWith(color: tone.lip)),
                    Text(advice.item.name, style: T.small.copyWith(color: tone.lip.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Pressable(
                onTap: onBack,
                child: Padding(
                  padding: const EdgeInsets.all(S.x1),
                  child: Icon(PhosphorIconsBold.arrowCounterClockwise, color: tone.lip, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Text(advice.reason, style: T.body.copyWith(color: C.ink.withValues(alpha: 0.8))),
          if (advice.pairWith.isNotEmpty) ...[
            const SizedBox(height: S.x3),
            Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('PAIR WITH', style: T.eyebrow.copyWith(color: tone.lip, fontSize: 11)),
                for (final f in advice.pairWith)
                  Pressable(
                    onTap: () => onPair(f),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
                      decoration: BoxDecoration(
                        color: C.surface,
                        borderRadius: BorderRadius.circular(R.chip),
                        border: Border.all(color: tone.face.withValues(alpha: 0.5), width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(f.icon, size: 16, color: C.soil),
                          const SizedBox(width: 4),
                          Text(
                            f.name,
                            style: T.small.copyWith(color: C.ink, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: S.x3),
          Row(
            children: [
              Icon(PhosphorIconsFill.lightning, size: 16, color: (avoid || followsTip) ? C.sunLip : C.faint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  xpLine,
                  style: T.small.copyWith(color: (avoid || followsTip) ? C.sunLip : C.muted, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x4),
          if (avoid)
            ChunkyButton(label: 'Keep it out', variant: variant, onPressed: onKeepOut)
          else ...[
            ChunkyButton(label: advice.verdict == Verdict.great ? 'Add it' : 'Add it carefully', variant: variant, onPressed: onAdd),
            const SizedBox(height: S.x2),
            ChunkyButton(label: 'Not now', variant: ChunkyVariant.ghost, height: 40, onPressed: onBack),
          ],
        ],
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child, required this.color, required this.edge});
  final Widget child;
  final Color color;
  final Color edge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: edge,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.card)),
      ),
      padding: const EdgeInsets.only(top: 2),
      child: Container(
        decoration: BoxDecoration(
          color: Color.alphaBlend(color, C.bg),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.card - 1)),
        ),
        padding: EdgeInsets.fromLTRB(S.gutter, S.x5, S.gutter, S.x4 + MediaQuery.paddingOf(context).bottom),
        child: child,
      ),
    );
  }
}
