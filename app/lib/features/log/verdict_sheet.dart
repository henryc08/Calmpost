import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Opens the verdict for [item]: checked against the live readings, so the
/// same scrap can get a different answer on a different day.
Future<void> showVerdictSheet(BuildContext context, FoodItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.paper,
    barrierColor: C.ink.withValues(alpha: 0.4),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.hero))),
    builder: (_) => _VerdictSheet(item: item),
  );
}

class _VerdictSheet extends ConsumerStatefulWidget {
  const _VerdictSheet({required this.item});
  final FoodItem item;

  @override
  ConsumerState<_VerdictSheet> createState() => _VerdictSheetState();
}

class _VerdictSheetState extends ConsumerState<_VerdictSheet> {
  late FoodItem _item = widget.item;
  Advice? _advice;

  @override
  void initState() {
    super.initState();
    _check(_item);
  }

  Future<void> _check(FoodItem item) async {
    setState(() {
      _item = item;
      _advice = null;
    });
    final advice = await ref.read(repositoryProvider).checkItem(item);
    if (!mounted || _item != item) return;
    advice.verdict == Verdict.great ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    setState(() => _advice = advice);
  }

  void _commit({required bool added}) {
    final advice = _advice!;
    final tips = ref.read(suggestionProvider)?.add.map((f) => f.id) ?? const <String>[];
    final out = ref.read(gameProvider.notifier).recordLog(advice, added: added, suggestedIds: tips);
    if (added) ref.read(repositoryProvider).logItem(advice.item);
    if (out.followed) {
      showToast(ref, 'Followed the next best action', xp: out.xp);
    } else if (!added) {
      showToast(ref, 'Kept ${advice.item.name.toLowerCase()} out', xp: out.xp);
    } else {
      showToast(ref, '${advice.item.name} logged');
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final a = _advice;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, S.x5 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: S.x5),
          AnimatedSize(duration: M.base, curve: M.ease, alignment: Alignment.topCenter, child: a == null ? _loading() : _result(a)),
        ],
      ),
    );
  }

  Widget _loading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_item.icon, size: 26, color: C.ink2),
            const SizedBox(width: S.x3),
            Expanded(child: Text(_item.name, style: T.title)),
          ],
        ),
        const SizedBox(height: S.x4),
        Text('Checking against the live readings…', style: T.body),
        const SizedBox(height: S.x4),
        const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          child: LinearProgressIndicator(minHeight: 4, color: C.brand, backgroundColor: C.sunk),
        ),
        const SizedBox(height: S.x6),
      ],
    );
  }

  Widget _result(Advice a) {
    final followsTip = ref.read(suggestionProvider)?.add.any((f) => f.id == a.item.id) ?? false;
    final (color, icon, label) = switch (a.verdict) {
      Verdict.great => (C.leaf, PhosphorIconsBold.check, 'GOOD TO ADD'),
      Verdict.careful => (C.amber, PhosphorIconsBold.exclamationMark, 'ADD WITH CARE'),
      Verdict.avoid => (C.clay, PhosphorIconsBold.prohibit, 'KEEP IT OUT'),
    };
    final avoid = a.verdict == Verdict.avoid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ).animate().scale(begin: const Offset(0.4, 0.4), duration: 420.ms, curve: Curves.easeOutBack),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: T.caps.copyWith(color: color)),
                  const SizedBox(height: 2),
                  Text(a.item.name, style: T.small.copyWith(color: C.ink2)),
                ],
              ),
            ),
            if (avoid || followsTip) PinkPill('+${avoid ? Xp.avoidedBadAdd : Xp.followedSuggestion} XP'),
          ],
        ),
        const SizedBox(height: S.x4),
        Text(a.headline, style: T.title.copyWith(fontSize: 28)),
        const SizedBox(height: S.x2),
        Text(a.reason, style: T.body.copyWith(fontSize: 15)),
        if (a.pairWith.isNotEmpty) ...[
          const SizedBox(height: S.x4),
          Text('PAIR IT WITH', style: T.caps),
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [for (final f in a.pairWith) Chip2(f.name, icon: f.icon, color: C.loam, onTap: () => _check(f))],
          ),
        ],
        const SizedBox(height: S.x4),
        Text(
          avoid
              ? 'Keeping it out earns ${Xp.avoidedBadAdd} XP.'
              : followsTip
              ? 'This is the next best action: +${Xp.followedSuggestion} XP.'
              : 'Adding scraps earns no XP on its own. Following the next best action does.',
          style: T.small,
        ),
        const SizedBox(height: S.x5),
        SizedBox(
          width: double.infinity,
          child: avoid
              ? PillButton(label: 'Keep it out', color: C.clay, textColor: Colors.white, onTap: () => _commit(added: false))
              : PillButton(label: a.verdict == Verdict.great ? 'Add it' : 'Add it carefully', onTap: () => _commit(added: true)),
        ),
        const SizedBox(height: S.x2),
        Center(
          child: Pressable(
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.all(S.x3),
              child: Text('Not now', style: T.button.copyWith(color: C.muted)),
            ),
          ),
        ),
      ],
    );
  }
}
