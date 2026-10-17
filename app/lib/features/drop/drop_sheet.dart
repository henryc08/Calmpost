import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/toast.dart';
import '../../data/food_catalog.dart';
import '../../data/calmpost_repository.dart';
import '../../domain/drop.dart';
import '../../domain/models.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../state/social.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'drop_review.dart';

/// Camera drop-in (AGENTS.md 2.4): arm the camera, drop the scrap in, then
/// review what it saw. Nothing is logged until the user says it's right.
Future<void> showDropSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.paper,
    barrierColor: C.ink.withValues(alpha: 0.4),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.hero))),
    builder: (_) => const DropSheet(),
  );
}

enum _Phase { arming, watching, nothing, failed, review, done }

class DropSheet extends ConsumerStatefulWidget {
  const DropSheet({super.key});

  @override
  ConsumerState<DropSheet> createState() => _DropSheetState();
}

class _DropSheetState extends ConsumerState<DropSheet> {
  _Phase _phase = _Phase.arming;
  DropSession? _session;
  Drop? _drop;
  DropTier _tier = DropTier.confident;
  List<DropLine> _lines = const [];
  List<Advice> _verdicts = const [];
  int _xp = 0;
  bool _saving = false;
  bool _needsBin = false;
  StreamSubscription<DropEvent>? _sub;
  Timer? _tick;
  late CalmpostRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(repositoryProvider);
    _arm();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    final session = _session;
    if (session != null && (_phase == _Phase.watching || _phase == _Phase.arming)) {
      unawaited(_repo.cancelDropSession(session).catchError((_) {}));
    }
    super.dispose();
  }

  Future<void> _arm() async {
    _sub?.cancel();
    _tick?.cancel();
    setState(() => _phase = _Phase.arming);
    try {
      final account = await ref.read(socialSessionProvider.future);
      if (!mounted) return;
      _needsBin = account != null && ref.read(dataSourceProvider) == DataSource.live && account.binId == null;
      if (_needsBin) {
        setState(() => _phase = _Phase.failed);
        return;
      }
      _repo = ref.read(repositoryProvider);
      final repo = _repo;
      final pending = await repo.pendingDrop();
      if (!mounted) return;
      if (pending != null) {
        _review(pending);
        return;
      }
      final session = await repo.startDropSession();
      if (!mounted) {
        await repo.cancelDropSession(session);
        return;
      }
      setState(() {
        _session = session;
        _phase = _Phase.watching;
      });
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      _sub = repo
          .watchDrop(session)
          .listen(
            (e) => switch (e) {
              DropSeen(:final drop) => _review(drop),
              DropNothing() => _end(_Phase.nothing),
            },
            onError: (_) => _end(_Phase.failed),
          );
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  void _end(_Phase phase) {
    _tick?.cancel();
    if (mounted) setState(() => _phase = phase);
  }

  void _review(Drop drop) {
    _tick?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _drop = drop;
      _tier = tierOf(drop, foodById);
      _lines = linesFor(drop, foodById);
      _phase = _Phase.review;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final drop = _drop!;
    setState(() => _saving = true);
    final tips = ref.read(suggestionProvider)?.add.map((f) => f.id).toSet() ?? const <String>{};
    try {
      final game = ref.read(gameProvider.notifier);
      final verdicts = await _repo.confirmReviewedDrop(drop, _lines, advisedIds: tips);
      if (!mounted) return;
      final xp = _repo.serverGame
          ? verdicts.fold<int>(0, (sum, a) => sum + (a.xpAwarded ?? 0))
          : game
                .recordDrop(verdicts, added: [for (final l in _lines) !l.removed], suggestedIds: tips, quantities: [for (final l in _lines) l.grams])
                .fold<int>(0, (sum, o) => sum + o.xp);
      ref.invalidate(inventoryProvider);
      if (_repo.serverGame) await game.refreshLive();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _verdicts = verdicts;
        _xp = xp;
        _saving = false;
        _phase = _Phase.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(ref, 'Couldn\'t save that. Check the connection and try again.');
    }
  }

  Future<void> _dismiss() async {
    final drop = _drop;
    setState(() => _saving = true);
    try {
      if (drop != null) await _repo.dismissReviewedDrop(drop);
      if (!mounted) return;
      showToast(ref, 'Got it. Nothing logged.');
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(ref, 'Could not dismiss this drop. Please retry.');
      }
    }
  }

  void _logByHand() {
    Navigator.of(context).pop();
    ref.read(tabProvider.notifier).state = AppTab.log;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, S.x5 + MediaQuery.paddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom),
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
          AnimatedSize(
            duration: M.base,
            curve: M.ease,
            alignment: Alignment.topCenter,
            child: KeyedSubtree(
              key: ValueKey(_phase),
              child: _body().animate().fadeIn(duration: 240.ms, curve: M.ease),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() => switch (_phase) {
    _Phase.arming => _message(icon: PhosphorIconsRegular.camera, title: 'Starting the camera…', body: 'One moment.', busy: true),
    _Phase.watching => _watching(),
    _Phase.nothing => _message(
      icon: PhosphorIconsRegular.eyeSlash,
      title: 'Didn\'t see anything',
      body: 'Nothing new showed up under the camera in the last minute.',
      primary: ('Try again', _arm),
      secondary: ('Log it by hand', _logByHand),
    ),
    _Phase.failed => _message(
      icon: PhosphorIconsRegular.cameraSlash,
      title: _needsBin ? 'Connect your bin first' : 'Couldn\'t reach the camera',
      body: _needsBin
          ? 'Connect your bin in Social, then return to review camera additions.'
          : 'The camera service on the laptop isn\'t answering. You can still log this by hand.',
      primary: ('Log it by hand', _logByHand),
      secondary: ('Try again', _arm),
    ),
    _Phase.review => DropReview(
      drop: _drop!,
      tier: _tier,
      lines: _lines,
      catalog: foodById,
      search: ref.read(repositoryProvider).searchFoods,
      saving: _saving,
      onChanged: (lines) => setState(() => _lines = lines),
      onSave: _save,
      onDismiss: _dismiss,
    ),
    _Phase.done => _done(),
  };

  Widget _watching() {
    final total = const Duration(seconds: 60).inMilliseconds;
    final left = _session == null ? total : _session!.expiresAt.difference(DateTime.now()).inMilliseconds.clamp(0, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LiveDot(color: C.brand),
            const SizedBox(width: S.x1),
            Text('BIN CAMERA REQUESTED', style: T.caps.copyWith(color: C.brandDeep)),
          ],
        ),
        const SizedBox(height: S.x2),
        Text('Watching the bin…', style: T.title),
        const SizedBox(height: S.x1),
        Text('Place your scraps under the bin camera. You\'ll check the photo and correct any mistakes before saving.', style: T.body),
        const SizedBox(height: S.x3),
        Text('Uses the bin’s camera, not your phone camera. Live preview is not available in this build.', style: T.small),
        const SizedBox(height: S.x6),
        Center(
          child: SizedBox(
            width: 132,
            height: 132,
            child: CustomPaint(
              painter: _Countdown(left / total),
              child: Center(
                child: Text('${(left / 1000).ceil()}', style: T.display.copyWith(color: C.ink)),
              ),
            ),
          ),
        ),
        const SizedBox(height: S.x6),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Not now', style: T.button.copyWith(color: C.muted)),
          ),
        ),
      ],
    );
  }

  Widget _done() {
    final fixed = corrected(_drop!, _lines);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('LOGGED', style: T.caps.copyWith(color: C.brandDeep)),
            ),
            if (_xp > 0) PinkPill('+$_xp XP'),
          ],
        ),
        const SizedBox(height: S.x2),
        Text(_verdicts.length == 1 ? _verdicts.first.headline : 'Here\'s what that does', style: T.title),
        const SizedBox(height: S.x4),
        for (final (i, a) in _verdicts.indexed) ...[if (i > 0) const Hairline(), _VerdictRow(advice: a, removed: _lines[i].removed)],
        if (fixed) ...[const SizedBox(height: S.x4), Text('Thanks for the fix. The camera uses corrections like this to get better in your bin.', style: T.small)],
        const SizedBox(height: S.x5),
        SizedBox(
          width: double.infinity,
          child: PillButton(label: 'Done', onTap: () => Navigator.of(context).pop()),
        ),
      ],
    );
  }

  Widget _message({required IconData icon, required String title, required String body, bool busy = false, (String, VoidCallback)? primary, (String, VoidCallback)? secondary}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 28, color: C.muted),
        const SizedBox(height: S.x3),
        Text(title, style: T.title),
        const SizedBox(height: S.x1),
        Text(body, style: T.body),
        const SizedBox(height: S.x5),
        if (busy)
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: LinearProgressIndicator(minHeight: 4, color: C.brand, backgroundColor: C.sunk),
          ),
        if (primary != null)
          SizedBox(
            width: double.infinity,
            child: PillButton(label: primary.$1, onTap: primary.$2),
          ),
        if (secondary != null)
          Center(
            child: TextButton(
              onPressed: secondary.$2,
              child: Text(secondary.$1, style: T.button.copyWith(color: C.muted)),
            ),
          ),
        const SizedBox(height: S.x2),
      ],
    );
  }
}

class _VerdictRow extends StatelessWidget {
  const _VerdictRow({required this.advice, required this.removed});
  final Advice advice;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (advice.verdict) {
      _ when removed => (C.leaf, PhosphorIconsBold.check, 'KEPT OUT'),
      Verdict.great => (C.leaf, PhosphorIconsBold.check, 'GOOD TO ADD'),
      Verdict.careful => (C.amber, PhosphorIconsBold.exclamationMark, 'ADD WITH CARE'),
      Verdict.avoid => (C.clay, PhosphorIconsBold.prohibit, 'TAKE IT OUT'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 15),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$label · ${advice.item.name}', style: T.caps.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(removed ? 'Thanks for taking it back out.' : advice.reason, style: T.small.copyWith(color: C.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Countdown extends CustomPainter {
  _Countdown(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final track = Paint()
      ..color = C.sunk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final arc = Paint()
      ..color = C.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, track);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * fraction, false, arc);
  }

  @override
  bool shouldRepaint(_Countdown old) => old.fraction != fraction;
}
