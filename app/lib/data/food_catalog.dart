import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../domain/models.dart';

/// Common kitchen items. The backend will replace this with Gemini + a real
/// lookup; the categories mirror its rule-based fallback.
const foodCatalog = <FoodItem>[
  // Greens: nitrogen, usually wet.
  FoodItem(
    id: 'banana_peel',
    name: 'Banana peel',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.orangeSlice,
    grams: 110,
    wet: true,
    note: 'Rich in potassium and breaks down fast.',
  ),
  FoodItem(
    id: 'veg_peels',
    name: 'Veggie peels',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.carrot,
    grams: 90,
    wet: true,
    note: 'Classic green: nitrogen for the microbes.',
  ),
  FoodItem(
    id: 'coffee_grounds',
    name: 'Coffee grounds',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.coffee,
    grams: 60,
    wet: true,
    note: 'A nitrogen boost. Worms love them.',
  ),
  FoodItem(
    id: 'apple_core',
    name: 'Apple core',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.appleLogo,
    grams: 70,
    wet: true,
    note: 'Juicy, so it adds moisture.',
  ),
  FoodItem(
    id: 'lettuce',
    name: 'Lettuce leaves',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.leaf,
    grams: 50,
    wet: true,
    note: 'Mostly water. Great when things are dry.',
  ),
  FoodItem(id: 'tea_bag', name: 'Tea bag', category: FoodCategory.green, icon: PhosphorIconsFill.teaBag, grams: 20, note: 'Check it\'s plastic-free first.'),
  FoodItem(
    id: 'eggshells',
    name: 'Eggshells',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.eggCrack,
    grams: 15,
    note: 'Crush them: calcium for your soil.',
  ),
  FoodItem(
    id: 'citrus',
    name: 'Citrus peel',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.orange,
    grams: 80,
    wet: true,
    note: 'Fine in small amounts; acidic in bulk.',
  ),
  FoodItem(
    id: 'avocado',
    name: 'Avocado skin',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.avocado,
    grams: 40,
    note: 'Slow to break down. Chop it up.',
  ),
  FoodItem(id: 'pepper', name: 'Pepper tops', category: FoodCategory.green, icon: PhosphorIconsFill.pepper, grams: 30, wet: true, note: 'Easy green.'),
  FoodItem(
    id: 'grass',
    name: 'Grass clippings',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.plant,
    grams: 120,
    wet: true,
    note: 'Heats things up fast. Thin layers only.',
  ),

  // For a drop the camera (or you) can't break down item by item. Only when
  // nothing from the keep-out list is in it: the drop pop-up asks.
  FoodItem(
    id: 'mixed_scraps',
    name: 'Mixed food scraps',
    category: FoodCategory.green,
    icon: PhosphorIconsFill.bowlFood,
    grams: 150,
    wet: true,
    note: 'Plate scrapings and leftovers: fine if there is no meat, dairy or oil in them.',
  ),
  // Browns: carbon, dry.
  FoodItem(
    id: 'cardboard',
    name: 'Shredded cardboard',
    category: FoodCategory.brown,
    icon: PhosphorIconsFill.package,
    grams: 40,
    note: 'Soaks up extra water and adds air.',
  ),
  FoodItem(
    id: 'newspaper',
    name: 'Newspaper',
    category: FoodCategory.brown,
    icon: PhosphorIconsFill.newspaper,
    grams: 35,
    note: 'Shred it. Skip glossy pages.',
  ),
  FoodItem(id: 'dry_leaves', name: 'Dry leaves', category: FoodCategory.brown, icon: PhosphorIconsFill.leaf, grams: 30, note: 'The gold standard brown.'),
  FoodItem(
    id: 'paper_towel',
    name: 'Paper towel',
    category: FoodCategory.brown,
    icon: PhosphorIconsFill.toiletPaper,
    grams: 10,
    note: 'Fine if it\'s not greasy or chemical.',
  ),
  FoodItem(id: 'egg_carton', name: 'Egg carton', category: FoodCategory.brown, icon: PhosphorIconsFill.egg, grams: 35, note: 'Tear it up into pieces.'),
  FoodItem(
    id: 'sawdust',
    name: 'Sawdust (untreated)',
    category: FoodCategory.brown,
    icon: PhosphorIconsFill.tree,
    grams: 30,
    note: 'Only from untreated wood.',
  ),

  // Keep out.
  FoodItem(
    id: 'meat',
    name: 'Meat scraps',
    category: FoodCategory.avoid,
    icon: PhosphorIconsFill.hamburger,
    grams: 0,
    note: 'Attracts pests and smells as it rots.',
  ),
  FoodItem(id: 'fish', name: 'Fish', category: FoodCategory.avoid, icon: PhosphorIconsFill.fish, grams: 0, note: 'Pests and strong odours.'),
  FoodItem(id: 'bones', name: 'Bones', category: FoodCategory.avoid, icon: PhosphorIconsFill.bone, grams: 0, note: 'Won\'t break down in a home bin.'),
  FoodItem(
    id: 'cheese',
    name: 'Cheese & dairy',
    category: FoodCategory.avoid,
    icon: PhosphorIconsFill.cheese,
    grams: 0,
    note: 'Turns sour and attracts pests.',
  ),
  FoodItem(
    id: 'oily_food',
    name: 'Oily leftovers',
    category: FoodCategory.avoid,
    icon: PhosphorIconsFill.pizza,
    grams: 0,
    note: 'Oil coats everything and stops airflow.',
  ),
  FoodItem(
    id: 'bread',
    name: 'Bread',
    category: FoodCategory.avoid,
    icon: PhosphorIconsFill.bread,
    grams: 0,
    note: 'Goes mouldy and draws pests in a small bin.',
  ),
];

final foodById = {for (final f in foodCatalog) f.id: f};
