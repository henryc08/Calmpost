import 'dart:typed_data';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'models.dart';
export 'models.dart' show DropSession;

/// Camera drop-in (AGENTS.md 2.4): what the camera saw, and the rules for the
/// "Is this right?" pop-up. The camera never logs anything by itself: every
/// drop is reviewed, and every row can be edited, because Gemini can be
/// confidently wrong.

enum Amount { small, handful, large }

/// Grams behind each amount; the backend uses the same table.
const amountGrams = {Amount.small: 40.0, Amount.handful: 110.0, Amount.large: 250.0};

Amount amountFor(double grams) => grams < 60 ? Amount.small : (grams < 180 ? Amount.handful : Amount.large);

/// Below this the row is marked "Check this".
const lowConfidence = 0.6;

const mixedScrapsId = 'mixed_scraps';

/// One thing the camera reported.
class Detection {
  const Detection({required this.label, required this.confidence, this.catalogId, this.category, this.amount, this.box, this.pieceCount, this.estimatedGrams});
  final String label;
  final int? pieceCount;
  final double? estimatedGrams;

  /// Null when the camera couldn't match it to the catalog.
  final String? catalogId;

  /// From the rules (backend), never from Gemini alone.
  final FoodCategory? category;
  final Amount? amount;
  final double confidence;

  /// [ymin, xmin, ymax, xmax] on 0-1000.
  final List<double>? box;
}

/// A detection waiting for the user.
class Drop {
  const Drop({required this.id, required this.items, this.geminiOk = true, this.thumbnail, this.source = 'camera'});
  final String source;
  bool get fromPhoto => source == 'photo';

  factory Drop.fromCamera(CameraDrop drop) => Drop(
    id: drop.id,
    source: drop.source,
    geminiOk: drop.geminiOk,
    thumbnail: drop.thumbnailJpeg,
    items: [
      for (final g in drop.guesses)
        Detection(
          label: g.label,
          confidence: g.confidence,
          catalogId: g.catalogId,
          category: g.category,
          amount: Amount.values.where((a) => a.name == g.amount).firstOrNull,
          box: g.box?.map((v) => v.toDouble()).toList(),
          pieceCount: g.pieceCount,
          estimatedGrams: g.estGrams,
        ),
    ],
  );
  final int id;
  final List<Detection> items;

  /// False when Gemini failed or timed out: the photo is all there is.
  final bool geminiOk;
  final Uint8List? thumbnail;
}

/// What happened in the armed window.
sealed class DropEvent {
  const DropEvent();
}

class DropSeen extends DropEvent {
  const DropSeen(this.drop);
  final Drop drop;
}

/// The window closed with nothing in it.
class DropNothing extends DropEvent {
  const DropNothing();
}

/// How sure the camera is, which decides how the pop-up asks.
enum DropTier {
  /// Everything matched with confidence: "Is this right?"
  confident,

  /// Some rows are low-confidence or unmatched: those are marked "Check this".
  check,

  /// Nothing usable (no items, Gemini failed, or a mix it couldn't separate):
  /// "Couldn't tell what went in", with a quick multi-pick.
  unclear,
}

DropTier tierOf(Drop d, Map<String, FoodItem> catalog) {
  if (!d.geminiOk || d.items.isEmpty) return DropTier.unclear;
  if (d.items.every((i) => !catalog.containsKey(i.catalogId))) {
    return DropTier.unclear;
  }
  if (d.items.any((i) => i.catalogId == mixedScrapsId)) return DropTier.unclear;
  if (d.items.any((i) => needsCheck(i, catalog))) return DropTier.check;
  return DropTier.confident;
}

bool needsCheck(Detection i, Map<String, FoodItem> catalog) =>
    !catalog.containsKey(i.catalogId) ||
    i.confidence < lowConfidence ||
    (i.category == FoodCategory.avoid && catalog[i.catalogId]?.category != FoodCategory.avoid);

/// One editable row in the pop-up.
class DropLine {
  const DropLine({
    required this.item,
    required this.amount,
    this.confidence,
    this.check = false,
    this.removed = false,
    this.fromCamera = false,
    this.pieceCount = 1,
    this.quantityG,
  });

  /// A catalog item, or a free-text one ([isCustom]) for things the catalog lacks.
  final FoodItem item;
  final Amount amount;
  final int pieceCount;
  final double? quantityG;
  double get grams => quantityG ?? amountGrams[amount]!;

  /// The camera's confidence; null for rows the user added.
  final double? confidence;

  /// Marked "Check this" until the user touches it.
  final bool check;

  /// A keep-out item the user took back out (logged as a skip: +5).
  final bool removed;
  final bool fromCamera;

  bool get isCustom => item.id.startsWith(customPrefix);
  bool get keepOut => item.category == FoodCategory.avoid;

  DropLine copyWith({FoodItem? item, Amount? amount, bool? check, bool? removed, int? pieceCount, double? quantityG}) => DropLine(
    item: item ?? this.item,
    amount: amount ?? this.amount,
    confidence: item != null && item.id != this.item.id ? null : confidence,
    check: check ?? this.check,
    removed: removed ?? (item != null && item.id != this.item.id ? false : this.removed),
    fromCamera: fromCamera,
    pieceCount: pieceCount ?? this.pieceCount,
    quantityG: quantityG ?? (amount == null ? this.quantityG : null),
  );
}

const customPrefix = 'custom:';

/// A free-text item the catalog doesn't have. The user picks its type.
FoodItem customFood(String label, FoodCategory category, Amount amount) => FoodItem(
  id: '$customPrefix${label.toLowerCase().trim()}',
  name: label.trim().isEmpty ? 'Something else' : label.trim()[0].toUpperCase() + label.trim().substring(1),
  category: keepOutLabel(label) ? FoodCategory.avoid : category,
  icon: PhosphorIconsFill.question,
  grams: amountGrams[amount]!,
  note: category == FoodCategory.avoid ? "It won't break down safely in a home bin." : '',
);

bool keepOutLabel(String label) => RegExp(
  r'\b(meat|chicken|beef|pork|bacon|fish|dairy|cheese|milk|butter|yogurt|oil|oily|grease|bone|bread|pet waste|cat litter|glossy)',
  caseSensitive: false,
).hasMatch(label);

/// The rows the pop-up starts with. Catalog items take the catalog's category
/// (rules); unmatched ones keep the camera's label as a custom item.
List<DropLine> linesFor(Drop d, Map<String, FoodItem> catalog) {
  return [
    for (final i in d.items)
      if (i.category == FoodCategory.avoid && catalog[i.catalogId]?.category != FoodCategory.avoid)
        DropLine(
          item: customFood(i.label, FoodCategory.avoid, i.amount ?? Amount.handful),
          amount: i.amount ?? Amount.handful,
          confidence: i.confidence,
          check: true,
          fromCamera: true,
          pieceCount: i.pieceCount ?? 1,
          quantityG: i.estimatedGrams,
        )
      else if (catalog[i.catalogId] case final food?)
        DropLine(
          item: food,
          amount: i.amount ?? amountFor(food.grams),
          confidence: i.confidence,
          check: needsCheck(i, catalog),
          fromCamera: true,
          pieceCount: i.pieceCount ?? 1,
          quantityG: i.estimatedGrams,
        )
      else
        DropLine(
          item: customFood(i.label, i.category ?? FoodCategory.green, i.amount ?? Amount.handful),
          amount: i.amount ?? Amount.handful,
          confidence: i.confidence,
          check: true,
          fromCamera: true,
          pieceCount: i.pieceCount ?? 1,
          quantityG: i.estimatedGrams,
        ),
  ];
}

/// The camera's first guess differs from what the user submits.
bool corrected(Drop d, List<DropLine> lines) {
  if (d.items.length != lines.length) return true;
  for (var i = 0; i < lines.length; i++) {
    final seen = d.items[i];
    final line = lines[i];
    if (seen.catalogId != line.item.id ||
        (seen.amount != null && seen.amount != line.amount) ||
        (seen.category != null && seen.category != line.item.category) ||
        (seen.pieceCount != null && seen.pieceCount != line.pieceCount) ||
        (seen.estimatedGrams != null && seen.estimatedGrams!.round() != line.grams.round()) ||
        line.removed) {
      return true;
    }
  }
  return false;
}
