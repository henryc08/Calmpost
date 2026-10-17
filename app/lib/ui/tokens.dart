import 'package:flutter/widgets.dart';

import '../domain/models.dart' show Rarity;

/// Colour tokens. Bright leaf-green paper, deep green text, pink as the reward accent.
/// No gradients, no glass, no purple.
abstract final class C {
  // Surfaces
  static const paper = Color(0xFF4BBC77);
  static const surface = Color(0xFF5BC584);
  static const sunk = Color(0xFF3EA867);
  static const line = Color(0xFF389F60);

  // Text
  static const ink = Color(0xFF0D2416);
  static const ink2 = Color(0xFF15402A);
  static const muted = Color(0xFF1E5838);
  static const faint = Color(0xFF2F7C51);

  // Forest: the hero surface and primary actions
  static const forest = Color(0xFF1F3A2E);
  static const forest2 = Color(0xFF2B4D3E);
  static const onForest = Color(0xFFEDEFE6);
  static const onForestMuted = Color(0xFF9DB3A6);

  // Accents
  static const sprout = Color(0xFFB9DD7B); // positive on dark
  static const leaf = Color(0xFF0E5A32); // positive on the green paper
  static const leafSoft = Color(0xFF8FD9A8);
  static const amber = Color(0xFFE39B3A); // streak
  static const amberSoft = Color(0xFFF6E6CC);
  static const water = Color(0xFF4F8FC9); // moisture / too wet
  static const waterSoft = Color(0xFFE1ECF6);
  static const clay = Color(0xFFC65A3E); // warnings / avoid
  static const claySoft = Color(0xFFF5E0D9);
  static const loam = Color(0xFF6B3F22); // currency

  // Pink: the reward accent (streak, XP, rewards, bloom). Use as a fill with dark text, never as text on green.
  static const pink = Color(0xFFFF66C4);
  static const pinkSoft = Color(0xFFF3A6D6);
  static const pinkDeep = Color(0xFFB8327F);
}

/// Gacha rarity colours.
Color rarityColor(Rarity r) => switch (r) {
  Rarity.common => const Color(0xFF9AA39D),
  Rarity.uncommon => const Color(0xFF3F8A5F),
  Rarity.rare => const Color(0xFF3F7FBF),
  Rarity.epic => const Color(0xFFC0623F),
  Rarity.legendary => const Color(0xFFD9A426),
};

/// Spacing on a 4/8 grid.
abstract final class S {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const gutter = 20.0;
}

/// Corner radii.
abstract final class R {
  static const pill = 999.0;
  static const chip = 10.0;
  static const tile = 16.0;
  static const panel = 22.0;
  static const hero = 28.0;
}

/// Motion timings.
abstract final class M {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 600);
  static const stagger = Duration(milliseconds: 50);
  static const ease = Cubic(0.2, 0.8, 0.2, 1);
}
