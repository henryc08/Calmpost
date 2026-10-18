import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/drop.dart';
import '../../domain/models.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import '../../ui/piece_counter.dart';
import 'drop_photo.dart';
import '../toronto/toronto_widgets.dart';

/// "Is this right?": always asked, even when the camera is sure, because
/// Gemini can be confidently wrong. Every row can be changed, removed or
/// added to. How much it asks depends on the [tier].
class DropReview extends StatefulWidget {
  const DropReview({
    super.key,
    required this.drop,
    required this.tier,
    required this.lines,
    required this.catalog,
    required this.search,
    required this.onChanged,
    required this.onSave,
    required this.onDismiss,
    this.saving = false,
  });

  final Drop drop;
  final DropTier tier;
  final List<DropLine> lines;
  final Map<String, FoodItem> catalog;
  final List<FoodItem> Function(String query) search;
  final ValueChanged<List<DropLine>> onChanged;
  final VoidCallback onSave;
  final VoidCallback onDismiss;
  final bool saving;

  @override
  State<DropReview> createState() => _DropReviewState();
}

/// Quick picks when the camera couldn't tell (common things that go in together).
const _quickPicks = [
  'mixed_scraps',
  'veg_peels',
  'banana_peel',
  'apple_core',
  'coffee_grounds',
  'tea_bag',
  'eggshells',
  'citrus',
  'lettuce',
  'cardboard',
  'paper_towel',
  'newspaper',
];

/// The safety question for a mix: these are always keep-out.
const _keepOutPicks = ['meat', 'fish', 'cheese', 'oily_food', 'bones'];

class _DropReviewState extends State<DropReview> {
  int? _editing;
  bool _edited = false;

  List<DropLine> get _lines => widget.lines;

  void _set(List<DropLine> lines, {bool edit = true}) {
    if (widget.saving) return;
    if (edit) _edited = true;
    widget.onChanged(lines);
  }

  void _replace(int i, DropLine line) => _set([..._lines]..[i] = line.copyWith(check: false));

  void _remove(int i) {
    HapticFeedback.selectionClick();
    setState(() => _editing = null);
    _set([..._lines]..removeAt(i));
  }

  void _toggle(FoodItem f) {
    HapticFeedback.selectionClick();
    final i = _lines.indexWhere((l) => l.item.id == f.id);
    setState(() => _editing = null);
    if (i >= 0) {
      _set([..._lines]..removeAt(i));
    } else {
      _set([..._lines, DropLine(item: f, amount: amountFor(f.grams))]);
    }
  }

  void _addBlank() {
    HapticFeedback.selectionClick();
    _set([..._lines, DropLine(item: customFood('', FoodCategory.green, Amount.handful), amount: Amount.handful, check: true)]);
    setState(() => _editing = _lines.length); // the new row, once the parent rebuilds
  }

  @override
  Widget build(BuildContext context) {
    final unclear = widget.tier == DropTier.unclear;
    final (caps, title, body) = switch (widget.tier) {
      DropTier.confident => ('SOMETHING WAS ADDED', 'Is this right?', 'Tap anything the camera got wrong.'),
      DropTier.check => ('SOMETHING WAS ADDED', 'Is this right?', 'The camera isn\'t sure about the marked items. Check them before saving.'),
      DropTier.unclear => (
        'COULDN\'T TELL',
        'What went in?',
        widget.drop.geminiOk
            ? 'It looked like a mix the camera couldn\'t pull apart. Pick what was in it, or call it mixed.'
            : 'The camera couldn\'t make it out. Pick what you dropped in.',
      ),
    };
    final saveLabel = widget.tier == DropTier.confident && !_edited ? 'Yes, that\'s right' : 'Save';
    final valid = _lines.isNotEmpty && _lines.every((l) => l.item.name != 'Something else' && (!l.keepOut || l.removed));
    final grams = _lines.where((l) => !l.keepOut && !l.removed).fold<double>(0, (sum, l) => sum + l.grams);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.drop.fromPhoto ? 'PHOTO REVIEW' : caps, style: T.caps.copyWith(color: unclear ? C.amber : C.brandDeep)),
        const SizedBox(height: S.x2),
        Text(title, style: T.title),
        const SizedBox(height: S.x1),
        Text(body, style: T.body),
        if (widget.drop.fromPhoto) Text('Confirm only scraps you actually added to the bin. A photo alone does not log compost.', style: T.small),
        const SizedBox(height: S.x4),
        DropPhoto(drop: widget.drop),
        if (widget.drop.items.isNotEmpty) ...[
          const SizedBox(height: S.x2),
          Text('Gemini’s original guess: ${widget.drop.items.map((i) => i.label).join(', ')}', style: T.small),
        ],
        const SizedBox(height: S.x4),
        if (_lines.isNotEmpty) ...[
          for (final (i, l) in _lines.indexed) ...[
            if (i > 0) const Hairline(),
            _LineRow(
              line: l,
              // In the unclear tier the whole screen is the question.
              showCheck: !unclear,
              open: _editing == i,
              onTap: () {
                if (!widget.saving) {
                  setState(() => _editing = _editing == i ? null : i);
                }
              },
              onRemovedChanged: (v) => _replace(i, l.copyWith(removed: v)),
            ),
            if (l.keepOut) ...[
              TorontoDestination(catalogId: l.item.id),
              const SizedBox(height: S.x2),
            ],
            if (_editing == i) _Editor(line: l, search: widget.search, onChanged: (line) => _replace(i, line), onRemove: () => _remove(i)),
          ],
          const Hairline(),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x2),
            child: Text('Nothing picked yet.', style: T.small),
          ),
        if (unclear) ...[
          const SizedBox(height: S.x5),
          const SectionLabel('WHAT WAS IN IT?'),
          const SizedBox(height: S.x3),
          _Picks(ids: _quickPicks, catalog: widget.catalog, lines: _lines, onTap: _toggle),
          const SizedBox(height: S.x5),
          const SectionLabel('ANY OF THESE IN IT?'),
          const SizedBox(height: S.x1),
          Text('They stay out of this compost bin. Check Toronto disposal guidance below each selected item.', style: T.small),
          const SizedBox(height: S.x3),
          _Picks(ids: _keepOutPicks, catalog: widget.catalog, lines: _lines, onTap: _toggle, color: C.clay),
        ] else
          Pressable(
            onTap: _addBlank,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x3),
              child: Row(
                children: [
                  const Icon(PhosphorIconsRegular.plus, size: 16, color: C.brandDeep),
                  const SizedBox(width: S.x2),
                  Expanded(child: Text('Add something it missed', style: T.button.copyWith(color: C.brandDeep))),
                ],
              ),
            ),
          ),
        const SizedBox(height: S.x5),
        Text('${grams.round()} g compostable · 1 XP per 20 g\nCare bonuses may apply. Daily action cap: 60 XP.', style: T.small),
        const SizedBox(height: S.x3),
        if (!valid && _lines.any((l) => l.keepOut && !l.removed))
          Padding(
            padding: const EdgeInsets.only(bottom: S.x3),
            child: Text('Confirm that keep-out items have been removed before saving.', style: T.small.copyWith(color: C.clay)),
          ),
        SizedBox(
          width: double.infinity,
          child: PillButton(label: widget.saving ? 'Saving…' : saveLabel, onTap: !valid || widget.saving ? null : widget.onSave),
        ),
        const SizedBox(height: S.x2),
        Center(
          child: TextButton(
            onPressed: widget.saving ? null : widget.onDismiss,
            child: Text('Nothing was added', style: T.button.copyWith(color: C.muted)),
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.open, required this.onTap, required this.onRemovedChanged, this.showCheck = true});
  final DropLine line;
  final bool showCheck;
  final bool open;
  final VoidCallback onTap;
  final ValueChanged<bool> onRemovedChanged;

  @override
  Widget build(BuildContext context) {
    final type = switch (line.item.category) {
      FoodCategory.green => 'Green',
      FoodCategory.brown => 'Brown',
      FoodCategory.avoid => 'Keep out',
    };
    final amount = switch (line.amount) {
      Amount.small => 'Small',
      Amount.handful => 'Handful',
      Amount.large => 'Large',
    };
    final sure = line.confidence == null ? '' : ' · ${(line.confidence! * 100).round()}% sure';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Pressable(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(
              children: [
                Icon(line.item.icon, size: 22, color: line.keepOut ? C.clay : C.ink2),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(line.item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.heading),
                          ),
                          if (line.check && showCheck) ...[const SizedBox(width: S.x2), const Badge2('Check this', color: C.amber, background: C.amberSoft)],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${line.pieceCount} × · $type · $amount ≈ ${line.grams.round()} g$sure',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.small.copyWith(color: line.keepOut ? C.clay : C.muted),
                      ),
                    ],
                  ),
                ),
                Icon(open ? PhosphorIconsRegular.caretUp : PhosphorIconsRegular.pencilSimple, size: 18, color: C.muted),
              ],
            ),
          ),
        ),
        if (line.keepOut)
          Padding(
            padding: const EdgeInsets.only(left: 34, bottom: S.x3),
            child: Pressable(
              onTap: () {
                HapticFeedback.selectionClick();
                onRemovedChanged(!line.removed);
              },
              child: Row(
                children: [
                  Icon(line.removed ? PhosphorIconsFill.checkSquare : PhosphorIconsRegular.square, size: 20, color: line.removed ? C.leaf : C.clay),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: Text(
                      line.removed ? 'Taken back out. Thank you.' : 'Take it back out, then tick here.',
                      style: T.small.copyWith(color: line.removed ? C.leaf : C.clay, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Fix one row: what it really was, its type (for things the catalog doesn't
/// know; catalog items take the catalog's type) and how much.
class _Editor extends StatefulWidget {
  const _Editor({required this.line, required this.search, required this.onChanged, required this.onRemove});
  final DropLine line;
  final List<FoodItem> Function(String) search;
  final ValueChanged<DropLine> onChanged;
  final VoidCallback onRemove;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final q = _query.text.trim();
    final matches = q.isEmpty ? const <FoodItem>[] : widget.search(q).take(5).toList();
    final exact = matches.any((f) => f.name.toLowerCase() == q.toLowerCase());

    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: S.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IT\'S ACTUALLY', style: T.caps.copyWith(fontSize: 10.5)),
          const SizedBox(height: S.x2),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: S.x3),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(R.pill),
              border: Border.all(color: C.line),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsRegular.magnifyingGlass, size: 16, color: C.muted),
                const SizedBox(width: S.x2),
                Expanded(
                  child: TextField(
                    controller: _query,
                    autofocus: l.isCustom && l.item.name == 'Something else',
                    onChanged: (_) => setState(() {}),
                    style: T.body.copyWith(color: C.ink),
                    decoration: InputDecoration.collapsed(hintText: l.isCustom ? 'What was it?' : 'Search, e.g. ${l.item.name.toLowerCase()}'),
                  ),
                ),
              ],
            ),
          ),
          if (q.isNotEmpty) ...[
            const SizedBox(height: S.x2),
            Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              children: [
                for (final f in matches)
                  Chip2(
                    f.name,
                    icon: f.icon,
                    onTap: () {
                      _query.clear();
                      widget.onChanged(l.copyWith(item: f, amount: amountFor(f.grams)));
                    },
                  ),
                if (!exact)
                  Chip2(
                    'Use "$q"',
                    icon: PhosphorIconsRegular.pencilSimple,
                    onTap: () {
                      _query.clear();
                      widget.onChanged(
                        l.copyWith(item: customFood(q, l.item.category == FoodCategory.avoid ? FoodCategory.avoid : FoodCategory.green, l.amount)),
                      );
                    },
                  ),
              ],
            ),
          ],
          if (l.isCustom) ...[
            const SizedBox(height: S.x4),
            Text('TYPE', style: T.caps.copyWith(fontSize: 10.5)),
            const SizedBox(height: S.x2),
            PaperSegments<FoodCategory>(
              values: const [FoodCategory.green, FoodCategory.brown, FoodCategory.avoid],
              selected: l.item.category,
              label: (c) => switch (c) {
                FoodCategory.green => 'Green',
                FoodCategory.brown => 'Brown',
                FoodCategory.avoid => 'Keep out',
              },
              onChanged: (c) => widget.onChanged(l.copyWith(item: customFood(l.item.name, c, l.amount))),
            ),
          ],
          const SizedBox(height: S.x4),
          PieceCounter(
            value: l.pieceCount,
            onChanged: (count) => widget.onChanged(l.copyWith(pieceCount: count)),
          ),
          const SizedBox(height: S.x4),
          Text('TOTAL AMOUNT', style: T.caps.copyWith(fontSize: 10.5)),
          const SizedBox(height: S.x2),
          PaperSegments<Amount>(
            values: Amount.values,
            selected: l.amount,
            label: (a) => switch (a) {
              Amount.small => 'Small',
              Amount.handful => 'Handful',
              Amount.large => 'Large',
            },
            onChanged: (a) => widget.onChanged(l.copyWith(amount: a, item: l.isCustom ? customFood(l.item.name, l.item.category, a) : null)),
          ),
          const SizedBox(height: S.x2),
          TextButton(
            onPressed: () async {
              final grams = await editCompostWeight(context, l.grams);
              if (grams != null && mounted) {
                widget.onChanged(widget.line.copyWith(quantityG: grams));
              }
            },
            child: Text('≈ ${l.grams.round()} g total · Edit weight', style: T.small),
          ),
          const SizedBox(height: S.x3),
          Pressable(
            onTap: widget.onRemove,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x2),
              child: Row(
                children: [
                  const Icon(PhosphorIconsRegular.trash, size: 16, color: C.clay),
                  const SizedBox(width: S.x2),
                  Text('Not in this drop', style: T.button.copyWith(color: C.clay)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tap-to-toggle catalog items for a drop the camera couldn't read.
class _Picks extends StatelessWidget {
  const _Picks({required this.ids, required this.catalog, required this.lines, required this.onTap, this.color = C.forest});
  final List<String> ids;
  final Map<String, FoodItem> catalog;
  final List<DropLine> lines;
  final ValueChanged<FoodItem> onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: S.x2,
      runSpacing: S.x2,
      children: [
        for (final id in ids)
          if (catalog[id] case final f?)
            Builder(
              builder: (context) {
                final on = lines.any((l) => l.item.id == id);
                return Pressable(
                  onTap: () => onTap(f),
                  scale: 0.96,
                  child: AnimatedContainer(
                    duration: M.fast,
                    padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                    decoration: BoxDecoration(
                      color: on ? color : Colors.transparent,
                      borderRadius: BorderRadius.circular(R.pill),
                      border: Border.all(color: on ? color : C.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(on ? PhosphorIconsBold.check : f.icon, size: 15, color: on ? Colors.white : (color == C.clay ? C.clay : C.ink2)),
                        const SizedBox(width: 6),
                        Text(f.name, style: T.small.copyWith(color: on ? Colors.white : C.ink, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              },
            ),
      ],
    );
  }
}
