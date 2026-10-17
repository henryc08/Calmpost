import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/toast.dart';
import '../../domain/models.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../state/social.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Camera drop-in (AGENTS.md 2.4): arm the camera, drop a scrap in, confirm
/// what it saw, get the usual verdict. The user always confirms: the camera
/// can be wrong. Data comes from CalmpostRepository's drop methods.
Future<void> showDropIn(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: false,
  backgroundColor: C.surface,
  barrierColor: C.ink.withValues(alpha: 0.4),
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.hero))),
  builder: (_) => const _DropSheet(),
);

enum _Phase { arming, watching, found, nothing, done, failed }

/// Small / Handful / Large in the pop-up; the API's amount strings.
const _amounts = ['small', 'handful', 'large'];

/// One row of the pop-up while the user edits it.
class _Row {
  _Row({required this.label, required this.food, required this.category, required this.amount, required this.confidence, this.box});

  factory _Row.fromGuess(DropGuess g) => _Row(
    label: g.item?.name ?? g.label,
    food: g.item,
    category: g.category ?? g.item?.category,
    amount: _amounts.contains(g.amount) ? g.amount! : 'handful',
    confidence: g.confidence,
    box: g.box,
  );

  String label;
  FoodItem? food;
  FoodCategory? category;
  String amount;
  final double confidence;
  final List<int>? box;

  /// A keep-out item the user has taken back out (+5 by the usual rule).
  bool removed = false;

  /// Fields under 60% are pre-highlighted "Check this".
  bool get unsure => confidence < 0.6;
  bool get ready => food != null && category != null;
}

class _DropSheet extends ConsumerStatefulWidget {
  const _DropSheet();

  @override
  ConsumerState<_DropSheet> createState() => _DropSheetState();
}

class _DropSheetState extends ConsumerState<_DropSheet> {
  _Phase _phase = _Phase.arming;
  DropSession? _session;
  CameraDrop? _drop;
  List<_Row> _rows = [];
  List<(FoodItem, Advice?)> _results = [];
  bool _busy = false;
  String? _error;
  StreamSubscription<List<CameraDrop>>? _sub;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _stopWatching() {
    _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
  }

  Future<void> _arm() async {
    _stopWatching();
    setState(() {
      _phase = _Phase.arming;
      _error = null;
    });
    final repo = ref.read(repositoryProvider);
    try {
      final s = await repo.startDropSession();
      if (!mounted) return;
      setState(() {
        _session = s;
        _phase = _Phase.watching;
      });
      // Count down; when the window ends with nothing seen, say so.
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _phase != _Phase.watching) return;
        if (!s.open) {
          _stopWatching();
          setState(() => _phase = _Phase.nothing);
        } else {
          setState(() {});
        }
      });
      // watchDrops lists every pending detection for the bin: take ours.
      _sub = repo.watchDrops().listen((drops) {
        final mine = drops.where((d) => d.sessionId == s.id && d.status == DropStatus.pending).firstOrNull;
        if (mine != null && mounted && _phase == _Phase.watching) _found(mine);
      }, onError: (_) {});
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  void _found(CameraDrop d) {
    _stopWatching();
    HapticFeedback.mediumImpact();
    setState(() {
      _drop = d;
      _rows = [for (final g in d.guesses) _Row.fromGuess(g)];
      if (_rows.isEmpty) {
        // Something moved but the camera couldn't name it: one row to fill in.
        _rows = [_Row(label: 'Choose an item', food: null, category: null, amount: 'handful', confidence: 0)];
      }
      _phase = _Phase.found;
    });
  }

  bool get _canSubmit => _rows.isNotEmpty && _rows.every((r) => r.ready);

  Future<void> _submit() async {
    if (_busy || !_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final tips = ref.read(suggestionProvider)?.add.map((f) => f.id).toSet() ?? const <String>{};
    final confirmations = [
      for (final r in _rows)
        DropConfirmation(
          label: r.food!.name,
          catalogId: r.food!.id,
          category: r.category,
          amount: r.amount,
          removed: r.category == FoodCategory.avoid && r.removed,
          wasAdvised: !r.removed && tips.contains(r.food!.id),
        ),
    ];
    try {
      final result = await ref.read(repositoryProvider).confirmDrop(_drop!.id, confirmations);
      if (!mounted) return;
      // Verdicts come back for each item that went in, in order.
      final verdicts = [...result.verdicts];
      final results = <(FoodItem, Advice?)>[];
      for (final (i, r) in _rows.indexed) {
        final removed = confirmations[i].removed;
        final advice = removed || verdicts.isEmpty ? null : verdicts.removeAt(0);
        results.add((r.food!, advice));
      }
      _recordLocally(results, confirmations, tips);
      HapticFeedback.lightImpact();
      setState(() {
        _results = results;
        _phase = _Phase.done;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save this drop. Check the connection and try again.';
        });
      }
    }
  }

  /// Signed out, the game runs on the phone: log each item with the same XP
  /// rules as the Log tab, tagged as a camera drop. Signed in, the backend
  /// already recorded it against the account.
  void _recordLocally(List<(FoodItem, Advice?)> results, List<DropConfirmation> sent, Set<String> tips) {
    if (ref.read(socialSessionProvider).valueOrNull != null) return;
    final game = ref.read(gameProvider.notifier);
    for (final (i, (food, advice)) in results.indexed) {
      if (sent[i].removed) {
        final out = game.recordLog(
          Advice(item: food, verdict: Verdict.avoid, headline: '', reason: ''),
          added: false,
          suggestedIds: const [],
          source: LogSource.camera,
        );
        showToast(ref, 'Kept ${food.name.toLowerCase()} out', xp: out.xp);
      } else if (advice != null && advice.verdict != Verdict.avoid) {
        final out = game.recordLog(advice, added: true, suggestedIds: tips, source: LogSource.camera);
        if (out.followed) showToast(ref, 'Followed the next best action', xp: out.xp);
      }
    }
  }

  Future<void> _nothingAdded() async {
    final d = _drop;
    if (d != null) unawaited(ref.read(repositoryProvider).dismissDrop(d.id).catchError((_) {}));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickFood(int i) async {
    final picked = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: C.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.hero))),
      builder: (_) => const _FoodPicker(),
    );
    if (picked != null && mounted) {
      setState(() {
        _rows[i]
          ..food = picked
          ..label = picked.name
          ..category = picked.category
          ..removed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Capped below the screen height so it scrolls (several items, large
    // text, small phones) instead of pushing the buttons off-screen.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      child: SingleChildScrollView(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: M.ease,
          child: Padding(
            padding: EdgeInsets.fromLTRB(S.gutter, S.x5, S.gutter, S.x5 + bottom),
            child: switch (_phase) {
              _Phase.arming || _Phase.watching => _watching(),
              _Phase.found => _foundView(),
              _Phase.done => _doneView(),
              _Phase.nothing => _message(PhosphorIconsRegular.eyeSlash, 'Didn\'t see anything', 'Nothing moved in the bin opening.'),
              _Phase.failed => _message(PhosphorIconsRegular.wifiSlash, 'Couldn\'t reach the camera', 'Check the bin is online, then try again.'),
            },
          ),
        ),
      ),
    );
  }

  Widget _watching() {
    final left = _session?.remaining.inSeconds ?? 60;
    return Column(
      key: const ValueKey('watching'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Watching the bin…', style: T.title),
        const SizedBox(height: S.x1),
        Text(_phase == _Phase.arming ? 'Getting the camera ready.' : 'Drop your scrap in now.', style: T.body),
        const SizedBox(height: S.x5),
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(child: CircularProgressIndicator(value: left / 60, strokeWidth: 4, color: C.brand, backgroundColor: C.sunk)),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$left', style: T.display.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  Text('seconds', style: T.small),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        Text('The camera only looks while this is open.', style: T.small, textAlign: TextAlign.center),
        const SizedBox(height: S.x4),
        PillButton(label: 'Cancel', color: C.surface, textColor: C.forest, onTap: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _foundView() {
    final d = _drop!;
    return Column(
      key: const ValueKey('found'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Something was added', style: T.title),
        if (!d.geminiOk || d.guesses.isEmpty) ...[
          const SizedBox(height: S.x1),
          Text(
            d.guesses.isEmpty ? 'The camera couldn\'t tell what it was. Fill it in below.' : 'This is a rough guess. Check it before you submit.',
            style: T.body,
          ),
        ],
        const SizedBox(height: S.x3),
        _Photo(photo: d.thumbnailJpeg, boxes: [for (final r in _rows) r.box]),
        for (final (i, r) in _rows.indexed) ...[
          const SizedBox(height: S.x3),
          if (_rows.length > 1) Text('ITEM ${i + 1}', style: T.caps),
          _ItemEditor(
            row: r,
            onPick: () => _pickFood(i),
            onCategory: (c) => setState(() {
              r.category = c;
              if (c != FoodCategory.avoid) r.removed = false;
            }),
            onAmount: (a) => setState(() => r.amount = a),
            onRemoved: (v) => setState(() => r.removed = v),
            onDelete: _rows.length > 1 ? () => setState(() => _rows.removeAt(i)) : null,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: S.x3),
          Text(_error!, style: T.small.copyWith(color: C.clay)),
        ],
        const SizedBox(height: S.x4),
        Row(
          children: [
            Expanded(child: PillButton(label: _busy ? 'Saving…' : 'Submit', onTap: _canSubmit && !_busy ? _submit : null)),
            const SizedBox(width: S.x2),
            PillButton(label: 'Nothing was added', color: C.surface, textColor: C.forest, dense: true, onTap: _busy ? null : _nothingAdded),
          ],
        ),
      ],
    );
  }

  Widget _doneView() {
    return Column(
      key: const ValueKey('done'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (food, advice)) in _results.indexed) ...[
          if (i > 0) const SectionBreak(),
          _VerdictResult(food: food, advice: advice),
        ],
        const SizedBox(height: S.x4),
        PillButton(label: 'Done', onTap: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _message(IconData icon, String title, String body) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36, color: C.muted),
        const SizedBox(height: S.x3),
        Text(title, style: T.title),
        const SizedBox(height: S.x1),
        Text(body, style: T.body, textAlign: TextAlign.center),
        const SizedBox(height: S.x5),
        Row(
          children: [
            Expanded(child: PillButton(label: 'Close', color: C.surface, textColor: C.forest, onTap: () => Navigator.of(context).pop())),
            const SizedBox(width: S.x2),
            Expanded(child: PillButton(label: 'Try again', onTap: _arm)),
          ],
        ),
      ],
    );
  }
}

/// The after-photo with a box around each item (box is 0-1000).
class _Photo extends StatelessWidget {
  const _Photo({required this.photo, required this.boxes});
  final Uint8List? photo;
  final List<List<int>?> boxes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.chip),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            fit: StackFit.expand,
            children: [
              if (photo != null)
                Image.memory(photo!, fit: BoxFit.cover, gaplessPlayback: true)
              else
                const ColoredBox(
                  color: C.loam,
                  child: Center(child: Icon(PhosphorIconsRegular.camera, color: C.onForestMuted, size: 32)),
                ),
              for (final b in boxes)
                if (b != null && b.length == 4)
                  Positioned(
                    top: b[0] / 1000 * c.maxHeight,
                    left: b[1] / 1000 * c.maxWidth,
                    height: (b[2] - b[0]) / 1000 * c.maxHeight,
                    width: (b[3] - b[1]) / 1000 * c.maxWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: C.brand, width: 2.5), borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({
    required this.row,
    required this.onPick,
    required this.onCategory,
    required this.onAmount,
    required this.onRemoved,
    this.onDelete,
  });
  final _Row row;
  final VoidCallback onPick;
  final ValueChanged<FoodCategory> onCategory;
  final ValueChanged<String> onAmount;
  final ValueChanged<bool> onRemoved;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final check = row.food == null || row.unsure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: onPick,
          child: Container(
            padding: const EdgeInsets.all(S.x3),
            decoration: BoxDecoration(color: check ? C.amberSoft : C.paper, borderRadius: BorderRadius.circular(R.chip)),
            child: Row(
              children: [
                Icon(row.food?.icon ?? PhosphorIconsRegular.question, size: 20, color: C.ink2),
                const SizedBox(width: S.x2),
                Expanded(child: Text(row.food?.name ?? row.label, style: T.heading.copyWith(fontSize: 15))),
                if (row.food != null && row.confidence > 0) Text('${(row.confidence * 100).round()}%', style: T.num.copyWith(color: C.muted)),
                if (check) ...[
                  const SizedBox(width: S.x2),
                  Text('Check this', style: T.small.copyWith(color: C.amber, fontWeight: FontWeight.w800)),
                ],
                const SizedBox(width: S.x1),
                const Icon(PhosphorIconsRegular.caretRight, size: 16, color: C.muted),
              ],
            ),
          ),
        ),
        const SizedBox(height: S.x2),
        Text('TYPE', style: T.caps),
        const SizedBox(height: S.x1),
        PaperSegments<FoodCategory>(
          values: FoodCategory.values,
          selected: row.category ?? FoodCategory.green,
          label: (c) => switch (c) {
            FoodCategory.green => 'Green',
            FoodCategory.brown => 'Brown',
            FoodCategory.avoid => 'Keep out',
          },
          onChanged: onCategory,
        ),
        if (row.category == FoodCategory.avoid) ...[
          const SizedBox(height: S.x2),
          Container(
            padding: const EdgeInsets.fromLTRB(S.x3, S.x2, S.x1, S.x2),
            decoration: BoxDecoration(color: C.claySoft, borderRadius: BorderRadius.circular(R.chip)),
            child: Row(
              children: [
                Expanded(child: Text('This should stay out of the bin. Did you take it back out?', style: T.small.copyWith(color: C.ink2))),
                Switch(value: row.removed, activeThumbColor: C.clay, onChanged: onRemoved),
              ],
            ),
          ),
        ],
        const SizedBox(height: S.x2),
        Text('AMOUNT', style: T.caps),
        const SizedBox(height: S.x1),
        PaperSegments<String>(
          values: _amounts,
          selected: row.amount,
          label: (a) => '${a[0].toUpperCase()}${a.substring(1)}',
          onChanged: onAmount,
        ),
        if (onDelete != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onDelete, child: Text('Remove this item', style: T.small.copyWith(color: C.clay))),
          ),
      ],
    );
  }
}

class _VerdictResult extends StatelessWidget {
  const _VerdictResult({required this.food, required this.advice});
  final FoodItem food;

  /// Null when the item was taken back out (no verdict needed).
  final Advice? advice;

  @override
  Widget build(BuildContext context) {
    final a = advice;
    final verdict = a?.verdict ?? Verdict.avoid;
    final (color, soft, icon, label) = switch (verdict) {
      Verdict.great => (C.leaf, C.leafSoft, PhosphorIconsBold.check, 'GOOD TO ADD'),
      Verdict.careful => (C.amber, C.amberSoft, PhosphorIconsBold.warning, 'ADD WITH CARE'),
      Verdict.avoid => (C.clay, C.claySoft, PhosphorIconsBold.x, 'KEEP IT OUT'),
    };
    final title = switch ((a, verdict)) {
      (null, _) => '${food.name}, kept out',
      (_, Verdict.avoid) => 'Take the ${food.name.toLowerCase()} back out',
      _ => '${food.name}, logged',
    };
    final body = a?.reason ?? 'Thanks for taking it back out. That keeps the bin healthy.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: S.x2),
            Text(label, style: T.caps.copyWith(color: color)),
          ],
        ),
        const SizedBox(height: S.x3),
        Text(title, style: T.title),
        const SizedBox(height: S.x1),
        Text(body, style: T.body),
        if (a != null && verdict != Verdict.avoid) ...[
          const SizedBox(height: S.x1),
          Text('Added by camera', style: T.small),
        ],
      ],
    ).animate().fadeIn(duration: 300.ms, curve: M.ease).slideY(begin: 0.04, end: 0);
  }
}

/// Search the catalog to correct what the camera saw.
class _FoodPicker extends ConsumerStatefulWidget {
  const _FoodPicker();

  @override
  ConsumerState<_FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends ConsumerState<_FoodPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final foods = ref.read(repositoryProvider).searchFoods(_q);
    return Padding(
      padding: EdgeInsets.fromLTRB(S.gutter, S.x5, S.gutter, MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What was it?', style: T.title),
          const SizedBox(height: S.x3),
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Banana peel',
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
              filled: true,
              fillColor: C.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.chip), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: S.x2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final f in foods)
                  ListTile(
                    leading: Icon(f.icon, color: C.ink2),
                    title: Text(f.name, style: T.body.copyWith(color: C.ink)),
                    trailing: Text(switch (f.category) {
                      FoodCategory.avoid => 'Keep out',
                      FoodCategory.green => 'Green',
                      FoodCategory.brown => 'Brown',
                    }, style: T.small),
                    onTap: () => Navigator.of(context).pop(f),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
