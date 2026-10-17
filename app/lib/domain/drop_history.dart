import 'models.dart';

class PastDropItem {
  const PastDropItem({required this.label, this.category = 'unknown', this.grams, this.pieces, this.removed = false});
  final String label, category;
  final double? grams;
  final int? pieces;
  final bool removed;
  factory PastDropItem.fromJson(Map<String, dynamic> j) => PastDropItem(
    label: j['label'] as String? ?? 'Unknown item',
    category: j['category'] as String? ?? 'unknown',
    grams: (j['quantity_g'] as num?)?.toDouble(),
    pieces: (j['piece_count'] as num?)?.toInt(),
    removed: j['removed'] == true,
  );
}

class PastDrop {
  const PastDrop({
    required this.id,
    required this.time,
    required this.status,
    required this.source,
    required this.guesses,
    this.items = const [],
    this.corrected = false,
    this.hasPhoto = false,
  });
  final int id;
  final DateTime time;
  final DropStatus status;
  final String source;
  final List<String> guesses;
  final List<PastDropItem> items;
  final bool corrected, hasPhoto;
  factory PastDrop.fromJson(Map<String, dynamic> j) => PastDrop(
    id: j['id'] as int,
    time: DateTime.parse(j['time'] as String).toLocal(),
    status: DropStatus.values.byName(j['status'] as String),
    source: j['source'] as String? ?? 'camera',
    guesses: [for (final item in j['items'] as List? ?? []) (item as Map)['label'] as String? ?? 'Unknown item'],
    items: [for (final item in j['final_items'] as List? ?? []) PastDropItem.fromJson(Map<String, dynamic>.from(item as Map))],
    corrected: j['corrected'] == true,
    hasPhoto: j['has_photo'] == true,
  );
}

class DropHistoryPage {
  const DropHistoryPage({required this.drops, this.nextBefore});
  final List<PastDrop> drops;
  // Keep the server cursor verbatim; DateTime formatting can lose precision.
  final String? nextBefore;
  factory DropHistoryPage.fromJson(Map<String, dynamic> j) => DropHistoryPage(
    drops: [for (final row in j['drops'] as List) PastDrop.fromJson(Map<String, dynamic>.from(row as Map))],
    nextBefore: j['next_before'] as String?,
  );
}
