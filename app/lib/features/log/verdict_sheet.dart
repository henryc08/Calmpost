import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/toast.dart';
import '../../domain/models.dart';
import '../../domain/drop.dart';
import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../state/social.dart';
import '../../data/social_repository.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import '../../ui/info_dot.dart';
import '../../ui/piece_counter.dart';

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
  String? _error;
  bool _saving = false;
  late Amount _amount = amountFor(widget.item.grams);
  int _pieceCount = 1;
  double? _weight;
  String _requestId = _newRequestId();
  static String _newRequestId() => 'manual-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  ({Advice advice, bool added, double grams, int pieces, bool advised})? _submission;

  @override
  void initState() {
    super.initState();
    _check(_item);
  }

  Future<void> _check(FoodItem item) async {
    if (_saving || _submission != null) return;
    setState(() {
      _item = item;
      _advice = null;
      _error = null;
      _amount = amountFor(item.grams);
      _pieceCount = 1;
      _weight = null;
      _requestId = _newRequestId();
    });
    try {
      final advice = await ref.read(repositoryProvider).checkItem(item);
      if (!mounted || _item != item) return;
      advice.verdict == Verdict.great ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
      setState(() => _advice = advice);
    } catch (_) {
      if (mounted && _item == item) {
        setState(() => _error = 'Could not check the bin. Nothing has been logged.');
      }
    }
  }

  Future<void> _commit({required bool added}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final advice = _advice!;
    final tips = ref.read(suggestionProvider)?.add.map((f) => f.id) ?? const <String>[];
    final submission = _submission ??= (advice: advice, added: added, grams: _weight ?? amountGrams[_amount]!, pieces: _pieceCount, advised: tips.contains(advice.item.id));
    final repo = ref.read(repositoryProvider);
    final game = ref.read(gameProvider.notifier);
    try {
      // Restoring secure storage is asynchronous. Do not mistake a loading
      // account for a signed-out demo and silently save to the wrong place.
      final account = await ref.read(socialSessionProvider.future);
      if (account != null) {
        if (account.binId == null || ref.read(dataSourceProvider) != DataSource.live) {
          throw const SocialFailure('Connect your bin in Social to save real care. Demo actions stay on this device.');
        }
        final result =
            await socialWrite(ref, 'POST', '/care-log', {
                  'catalog_id': submission.advice.item.id,
                  'action': submission.added ? 'added' : 'skipped',
                  'quantity_g': submission.added ? submission.grams.round() : 0,
                  'piece_count': submission.pieces,
                  'request_id': _requestId,
                })
                as Json;
        ref.invalidate(inventoryProvider);
        await game.refreshLive();
        if (!mounted) return;
        showToast(ref, 'Care saved to your profile', xp: result['xp_awarded'] as int);
        Navigator.of(context).pop();
        return;
      }
      final paid = await repo.logItem(
        submission.advice.item,
        added: submission.added,
        quantityG: submission.grams,
        pieceCount: submission.pieces,
        requestId: _requestId,
        wasAdvised: submission.advised,
      );
      final xp = repo.serverGame ? paid ?? 0 : game.recordLog(advice, added: added, suggestedIds: tips, quantityG: submission.grams).xp;
      ref.invalidate(inventoryProvider);
      if (repo.serverGame) await game.refreshLive();
      if (!mounted) return;
      showToast(ref, added ? '${advice.item.name} logged' : 'Kept ${advice.item.name.toLowerCase()} out', xp: xp);
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is SocialFailure ? error.message : 'Save was not confirmed. Retry the same entry to avoid duplicates.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _advice;
    return SingleChildScrollView(
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
          if (_error != null) ...[
            Text(_error!, style: T.body.copyWith(color: C.clay)),
            if (a == null) PillButton(label: 'Try again', onTap: () => _check(_item)),
            const SizedBox(height: S.x3),
          ],
          AnimatedSize(duration: M.base, curve: M.ease, alignment: Alignment.topCenter, child: a == null ? (_error == null ? _loading() : const SizedBox.shrink()) : _result(a)),
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
                  Row(
                    children: [
                      Text(label, style: T.caps.copyWith(color: color)),
                      const InfoDot(InfoTip.verdict),
                    ],
                  ),
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
              : 'Compostable additions earn 1 XP per 20 g.${followsTip ? ' Plus 15 XP for following this advice.' : ''} Action rewards are capped at 60 XP a day.',
          style: T.small,
        ),
        const SizedBox(height: S.x5),
        if (!avoid) ...[
          PieceCounter(value: _pieceCount, onChanged: _saving || _submission != null ? null : (count) => setState(() => _pieceCount = count)),
          const SizedBox(height: S.x3),
          Text('TOTAL AMOUNT · ESTIMATED', style: T.caps),
          const SizedBox(height: S.x2),
          PaperSegments<Amount>(
            values: Amount.values,
            selected: _amount,
            label: (a) => '${a.name} ${amountGrams[a]!.round()} g',
            onChanged: (a) {
              if (!_saving && _submission == null) {
                setState(() {
                  _amount = a;
                  _weight = null;
                });
              }
            },
          ),
          TextButton(
            onPressed: _saving || _submission != null
                ? null
                : () async {
                    final grams = await editCompostWeight(context, _weight ?? amountGrams[_amount]!);
                    if (grams != null && mounted) {
                      setState(() => _weight = grams);
                    }
                  },
            child: Text('≈ ${(_weight ?? amountGrams[_amount]!).round()} g total · Edit weight', style: T.small),
          ),
          const SizedBox(height: S.x4),
        ],
        SizedBox(
          width: double.infinity,
          child: avoid
              ? PillButton(label: _saving ? 'Saving…' : 'Keep it out', color: C.clay, textColor: Colors.white, onTap: _saving ? null : () => _commit(added: false))
              : PillButton(label: _saving ? 'Saving…' : (a.verdict == Verdict.great ? 'Add it' : 'Add it carefully'), onTap: _saving ? null : () => _commit(added: true)),
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
