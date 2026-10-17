"""Food catalog -- GENERATED from app/lib/data/food_catalog.dart.

The app owns this list. Do not edit by hand: change the Dart file, then run
`python -m scripts.sync_catalogs`. tests/test_parity.py fails on drift.
"""

FOOD: list[dict] = [
    {'id': 'banana_peel', 'name': 'Banana peel', 'category': 'green', 'grams': 110.0, 'wet': True, 'note': 'Rich in potassium and breaks down fast.'},
    {'id': 'veg_peels', 'name': 'Veggie peels', 'category': 'green', 'grams': 90.0, 'wet': True, 'note': 'Classic green: nitrogen for the microbes.'},
    {'id': 'coffee_grounds', 'name': 'Coffee grounds', 'category': 'green', 'grams': 60.0, 'wet': True, 'note': 'A nitrogen boost. Worms love them.'},
    {'id': 'apple_core', 'name': 'Apple core', 'category': 'green', 'grams': 70.0, 'wet': True, 'note': 'Juicy, so it adds moisture.'},
    {'id': 'lettuce', 'name': 'Lettuce leaves', 'category': 'green', 'grams': 50.0, 'wet': True, 'note': 'Mostly water. Great when things are dry.'},
    {'id': 'tea_bag', 'name': 'Tea bag', 'category': 'green', 'grams': 20.0, 'wet': False, 'note': "Check it's plastic-free first."},
    {'id': 'eggshells', 'name': 'Eggshells', 'category': 'green', 'grams': 15.0, 'wet': False, 'note': 'Crush them: calcium for your soil.'},
    {'id': 'citrus', 'name': 'Citrus peel', 'category': 'green', 'grams': 80.0, 'wet': True, 'note': 'Fine in small amounts; acidic in bulk.'},
    {'id': 'avocado', 'name': 'Avocado skin', 'category': 'green', 'grams': 40.0, 'wet': False, 'note': 'Slow to break down. Chop it up.'},
    {'id': 'pepper', 'name': 'Pepper tops', 'category': 'green', 'grams': 30.0, 'wet': True, 'note': 'Easy green.'},
    {'id': 'grass', 'name': 'Grass clippings', 'category': 'green', 'grams': 120.0, 'wet': True, 'note': 'Heats things up fast. Thin layers only.'},
    {'id': 'mixed_scraps', 'name': 'Mixed food scraps', 'category': 'green', 'grams': 150.0, 'wet': True, 'note': 'Plate scrapings and leftovers: fine if there is no meat, dairy or oil in them.'},
    {'id': 'cardboard', 'name': 'Shredded cardboard', 'category': 'brown', 'grams': 40.0, 'wet': False, 'note': 'Soaks up extra water and adds air.'},
    {'id': 'newspaper', 'name': 'Newspaper', 'category': 'brown', 'grams': 35.0, 'wet': False, 'note': 'Shred it. Skip glossy pages.'},
    {'id': 'dry_leaves', 'name': 'Dry leaves', 'category': 'brown', 'grams': 30.0, 'wet': False, 'note': 'The gold standard brown.'},
    {'id': 'paper_towel', 'name': 'Paper towel', 'category': 'brown', 'grams': 10.0, 'wet': False, 'note': "Fine if it's not greasy or chemical."},
    {'id': 'egg_carton', 'name': 'Egg carton', 'category': 'brown', 'grams': 35.0, 'wet': False, 'note': 'Tear it up into pieces.'},
    {'id': 'sawdust', 'name': 'Sawdust (untreated)', 'category': 'brown', 'grams': 30.0, 'wet': False, 'note': 'Only from untreated wood.'},
    {'id': 'meat', 'name': 'Meat scraps', 'category': 'avoid', 'grams': 0.0, 'wet': False, 'note': 'Attracts pests and smells as it rots.'},
    {'id': 'fish', 'name': 'Fish', 'category': 'avoid', 'grams': 0.0, 'wet': False, 'note': 'Pests and strong odours.'},
    {'id': 'bones', 'name': 'Bones', 'category': 'avoid', 'grams': 0.0, 'wet': False, 'note': "Won't break down in a home bin."},
    {'id': 'cheese', 'name': 'Cheese & dairy', 'category': 'avoid', 'grams': 0.0, 'wet': False, 'note': 'Turns sour and attracts pests.'},
    {'id': 'oily_food', 'name': 'Oily leftovers', 'category': 'avoid', 'grams': 0.0, 'wet': False, 'note': 'Oil coats everything and stops airflow.'},
    {'id': 'bread', 'name': 'Bread', 'category': 'avoid', 'grams': 0.0, 'wet': False, 'note': 'Goes mouldy and draws pests in a small bin.'},
]

BY_ID: dict[str, dict] = {f["id"]: f for f in FOOD}
BY_NAME: dict[str, dict] = {f["name"].lower(): f for f in FOOD}


def lookup(text: str | None) -> dict | None:
    """A catalog item by id or name, case-insensitive."""
    if not text:
        return None
    t = text.strip().lower()
    return BY_ID.get(t) or BY_NAME.get(t) or BY_ID.get(t.replace(" ", "_"))
