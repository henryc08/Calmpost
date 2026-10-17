/// Curated learning cards, available offline. Game abilities are fictional;
/// these general composting lessons come from EPA guidance, not the plant art.
class SeedLesson {
  const SeedLesson(this.title, this.fact, this.action);
  final String title;
  final String fact;
  final String action;
  static const source = 'https://www.epa.gov/recycle/composting-home';
}

const seedLessons = [
  SeedLesson(
    'Small scraps, living soil',
    'Microorganisms turn organic leftovers into compost, returning nutrients to soil.',
    'Keep a container for fruit and vegetable scraps.',
  ),
  SeedLesson(
    'Water has somewhere to stay',
    'Finished compost helps soil absorb and retain water, supporting gardens through dry weather.',
    'Use mature compost as a soil amendment.',
  ),
  SeedLesson(
    'Browns belong here too',
    'Microbes need carbon-rich browns as well as nitrogen-rich greens.',
    'Keep dry leaves or plain shredded cardboard beside your bin.',
  ),
  SeedLesson(
    'Give the tiny workers air',
    'Composting microbes need oxygen. Turning the pile helps air reach them.',
    'If a pile smells bad, check moisture and airflow.',
  ),
  SeedLesson('Damp, not drenched', 'Microbes need moisture, but an overly wet pile can smell and need more air.', 'Aim for the feel of a wrung-out sponge.'),
  SeedLesson(
    'Keep materials in the loop',
    'Composting recycles suitable kitchen and garden material instead of sending it to disposal.',
    'Remove produce stickers before logging your scraps.',
  ),
];

const _lessonSeeds = [
  ['sprout', 'basil', 'carrot', 'golden_sprout'],
  ['fern', 'potted', 'oak', 'ghost_orchid'],
  ['clover', 'wheat', 'pine', 'acorn'],
  ['pepper', 'feather', 'firefern', 'butterfly_bush'],
  ['cactus', 'lotus', 'frost', 'night_moss'],
  ['tulip', 'citrus', 'palm', 'bloom'],
];

SeedLesson lessonForSeed(String id) => seedLessons[_lessonSeeds.indexWhere((ids) => ids.contains(id)).clamp(0, seedLessons.length - 1)];

const fantasySeeds = {'night_moss', 'firefern', 'frost', 'golden_sprout'};
