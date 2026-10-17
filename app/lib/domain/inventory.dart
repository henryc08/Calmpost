/// Confirmed inputs over time. Decomposition means this is not a measurement
/// of what physically remains in the bin. Counts and grams are independent.
class InventoryItem {
  const InventoryItem({
    required this.key,
    required this.label,
    required this.category,
    required this.grams,
    required this.pieces,
    required this.entries,
    required this.uncountedEntries,
    required this.visionEntries,
    required this.lastAddedAt,
  });
  final String key, label, category;
  final double grams;
  final int pieces, entries, uncountedEntries, visionEntries;
  final DateTime lastAddedAt;

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
    key: '${j['item_key']}:${j['category']}',
    label: j['label'] as String,
    category: j['category'] as String,
    grams: (j['grams'] as num).toDouble(),
    pieces: (j['pieces'] as num).toInt(),
    entries: (j['entries'] as num).toInt(),
    uncountedEntries: (j['uncounted_entries'] as num).toInt(),
    visionEntries: (j['vision_entries'] as num).toInt(),
    lastAddedAt: DateTime.parse(j['last_added_at'] as String).toLocal(),
  );
}

class CompostInventory {
  const CompostInventory({this.items = const [], this.totalXp, this.volumeXp, this.careXp});
  final List<InventoryItem> items;
  // Null in the mock: account scores are computed from the backend ledger.
  final int? totalXp, volumeXp, careXp;
  double get grams => items.fold(0, (sum, i) => sum + i.grams);
  double gramsFor(String category) => items.where((i) => i.category == category).fold(0, (sum, i) => sum + i.grams);
  int get pieces => items.fold(0, (sum, i) => sum + i.pieces);
  int get entries => items.fold(0, (sum, i) => sum + i.entries);
  int get uncountedEntries => items.fold(0, (sum, i) => sum + i.uncountedEntries);
  factory CompostInventory.fromJson(Map<String, dynamic> j) => CompostInventory(
    items: [for (final i in j['items'] as List) InventoryItem.fromJson(i as Map<String, dynamic>)],
    totalXp: (j['total_xp'] as num?)?.toInt(),
    volumeXp: (j['volume_xp'] as num?)?.toInt(),
    careXp: (j['care_xp'] as num?)?.toInt(),
  );
}

String compostMass(double grams) => grams >= 1000 ? '${(grams / 1000).toStringAsFixed(2)} kg' : '${grams.round()} g';
