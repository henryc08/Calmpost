/// Toronto municipal sorting is independent of Calmpost bin care and rewards.
enum TorontoRoute { green, recycling, garbage, yard, lawn }

extension TorontoRouteLabel on TorontoRoute {
  String get label => switch (this) {
    TorontoRoute.green => 'Green Bin',
    TorontoRoute.recycling => 'Recycling',
    TorontoRoute.garbage => 'Garbage',
    TorontoRoute.yard => 'Yard waste',
    TorontoRoute.lawn => 'Leave on lawn',
  };
}

class TorontoSource {
  const TorontoSource(this.title, this.url);
  final String title, url;
  factory TorontoSource.fromJson(Map<String, dynamic> j) {
    final url = j['url'] as String;
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        ![
          'www.toronto.ca',
          'open.toronto.ca',
          'www.circularmaterials.ca',
        ].contains(uri.host)) {
      throw const FormatException('Unexpected Toronto source');
    }
    return TorontoSource(j['title'] as String, url);
  }
}

class TorontoItem {
  TorontoItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      route = TorontoRoute.values.byName(j['route'] as String),
      catalogIds = List<String>.unmodifiable(j['catalog_ids'] as List),
      aliases = List<String>.unmodifiable(j['aliases'] as List),
      action = j['action'] as String,
      source = j['source'] as String,
      sourceItem = j['source_item'] as String,
      sourceCategory = j['source_category'] as String;
  final String id, name, action, source, sourceItem, sourceCategory;
  final TorontoRoute route;
  final List<String> catalogIds, aliases;
}

class TorontoData {
  TorontoData.fromJson(Map<String, dynamic> j)
    : reviewedAt = j['reviewed_at'] as String,
      provenance = Map<String, dynamic>.unmodifiable(j['provenance'] as Map),
      stats = Map<String, dynamic>.unmodifiable(j['stats'] as Map),
      sources = Map<String, TorontoSource>.unmodifiable(
        (j['sources'] as Map<String, dynamic>).map(
          (k, v) =>
              MapEntry(k, TorontoSource.fromJson(v as Map<String, dynamic>)),
        ),
      ),
      items = List<TorontoItem>.unmodifiable(
        (j['items'] as List).map(
          (i) => TorontoItem.fromJson(i as Map<String, dynamic>),
        ),
      ) {
    if (j['version'] != 1 ||
        items.isEmpty ||
        items.map((i) => i.id).toSet().length != items.length) {
      throw const FormatException('Invalid Toronto dataset');
    }
    final mapped = <String>{};
    for (final item in items) {
      if (!sources.containsKey(item.source) ||
          item.catalogIds.any((id) => !mapped.add(id))) {
        throw const FormatException('Ambiguous Toronto mapping');
      }
    }
    for (final id in [
      'green',
      'reports',
      'strategy',
      'wizard',
      'apartments',
      'election',
    ]) {
      if (!sources.containsKey(id)) {
        throw const FormatException('Missing civic source');
      }
    }
    for (final key in [
      'multi_residential_diversion_pct',
      'single_family_diversion_pct',
      'green_bin_share_of_garbage_pct',
    ]) {
      final value = stats[key];
      if (value is! num || !value.isFinite || value < 0 || value > 100) {
        throw const FormatException('Invalid city statistic');
      }
    }
    for (final q in [...torontoBefore, ...torontoAfter]) {
      byId(q.itemId); // All quiz answers must exist in the imported data.
    }
    for (final lesson in torontoLessons) {
      for (final id in lesson.itemIds) {
        byId(id);
      }
    }
  }
  final String reviewedAt;
  final Map<String, dynamic> provenance, stats;
  final Map<String, TorontoSource> sources;
  final List<TorontoItem> items;
  TorontoItem byId(String id) => items.firstWhere((i) => i.id == id);
  TorontoItem? forCatalog(String id) =>
      items.where((i) => i.catalogIds.contains(id)).firstOrNull;
  List<TorontoItem> search(String query) {
    final words = query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    return items.where((i) {
      final haystack = '${i.name} ${i.aliases.join(' ')}'.toLowerCase();
      return words.every(haystack.contains);
    }).toList();
  }

  int score(
    Map<String, TorontoRoute> answers,
    List<TorontoQuestion> questions,
  ) => questions.where((q) => answers[q.itemId] == byId(q.itemId).route).length;
}

class TorontoQuestion {
  const TorontoQuestion(this.itemId, this.prompt);
  final String itemId, prompt;
}

const torontoBefore = [
  TorontoQuestion('A1334', 'An unpackaged cheese rind'),
  TorontoQuestion('A0688', 'A fork made of compostable plastic'),
  TorontoQuestion('A0304', 'An empty, clean paper egg carton'),
];
const torontoAfter = [
  TorontoQuestion('A1318', 'Chicken bones with no packaging'),
  TorontoQuestion('A0687', 'A cup made of compostable plastic'),
  TorontoQuestion('A0311', 'A clean newspaper with the wrapper removed'),
];

class TorontoLesson {
  const TorontoLesson(this.id, this.title, this.body, this.itemIds);
  final String id, title, body;
  final List<String> itemIds;
}

const torontoLessons = [
  TorontoLesson(
    'food',
    'Same scrap. Different system.',
    'Your small compost bin and Toronto’s Green Bin have different rules. City processing accepts meat, bones and dairy. Keep these out of your Calmpost compost bin.',
    ['A1334', 'A1318'],
  ),
  TorontoLesson(
    'packaging',
    'The label is not the destination.',
    'Compostable plastic packaging is not accepted in Toronto’s Green Bin. Separate food from packaging, and use reusables when you can.',
    ['A0688', 'A0687'],
  ),
  TorontoLesson(
    'paper',
    'Clean paper has another route.',
    'Clean paper and cardboard belong in recycling. Food-soiled, uncoated paper can go in organics. Paper contaminated with cleaning chemicals belongs in garbage.',
    ['A0304', 'A0311', 'A1447'],
  ),
];

/// Local learning evidence, never uploaded as XP, compost mass or city statistics.
class TorontoProgress {
  TorontoProgress({
    Map<String, TorontoRoute> before = const {},
    Map<String, TorontoRoute> after = const {},
    Set<String> learned = const {},
    Set<String> applied = const {},
  }) : before = Map.unmodifiable(before),
       after = Map.unmodifiable(after),
       learned = Set.unmodifiable(learned),
       applied = Set.unmodifiable(applied);
  final Map<String, TorontoRoute> before, after;
  final Set<String> learned, applied;
  bool get baselineDone => before.length == torontoBefore.length;
  bool get lessonsDone => learned.length == torontoLessons.length;
  bool get complete =>
      baselineDone && lessonsDone && after.length == torontoAfter.length;
  TorontoProgress answer(
    String id,
    TorontoRoute answer, {
    required bool followUp,
  }) {
    final questions = followUp ? torontoAfter : torontoBefore;
    final existing = followUp ? after : before;
    if (existing.length >= questions.length ||
        (followUp && (!baselineDone || !lessonsDone)) ||
        existing.containsKey(id) ||
        questions[existing.length].itemId != id) {
      return this;
    }
    return TorontoProgress(
      before: followUp ? before : {...before, id: answer},
      after: followUp ? {...after, id: answer} : after,
      learned: learned,
      applied: applied,
    );
  }

  TorontoProgress learn(String id) {
    if (!baselineDone ||
        learned.contains(id) ||
        !torontoLessons.any((l) => l.id == id)) {
      return this;
    }
    return TorontoProgress(
      before: before,
      after: after,
      learned: {...learned, id},
      applied: applied,
    );
  }

  TorontoProgress apply(String id) => TorontoProgress(
    before: before,
    after: after,
    learned: learned,
    applied: {...applied, id},
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'before': before.map((k, v) => MapEntry(k, v.name)),
    'after': after.map((k, v) => MapEntry(k, v.name)),
    'learned': learned.toList(),
    'applied': applied.toList(),
  };
  factory TorontoProgress.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) {
      throw const FormatException('Unknown learning version');
    }
    Map<String, TorontoRoute> answers(
      String key,
      List<TorontoQuestion> questions,
    ) {
      final raw = j[key] as Map<String, dynamic>;
      final result = <String, TorontoRoute>{};
      for (final q in questions) {
        if (!raw.containsKey(q.itemId)) break;
        result[q.itemId] = TorontoRoute.values.byName(raw[q.itemId] as String);
      }
      return result;
    }

    final before = answers('before', torontoBefore);
    final learned = (j['learned'] as List)
        .cast<String>()
        .where((id) => torontoLessons.any((l) => l.id == id))
        .toSet();
    return TorontoProgress(
      before: before,
      learned: before.length == torontoBefore.length ? learned : {},
      after:
          before.length == torontoBefore.length &&
              learned.length == torontoLessons.length
          ? answers('after', torontoAfter)
          : {},
      applied: (j['applied'] as List).cast<String>().toSet(),
    );
  }
}
