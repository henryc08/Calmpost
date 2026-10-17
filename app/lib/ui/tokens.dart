import 'package:flutter/widgets.dart';

/// Colour tokens. Flora-soft base, Duolingo-saturated accents.
/// Every accent comes as a trio: face, lip (the darker 3D edge) and tint.
abstract final class C {
  // Base
  static const bg = Color(0xFFFBF7EF);
  static const bgDeep = Color(0xFFF3ECDD);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFEEE7DA);
  static const borderDark = Color(0xFFDFD5C2);
  static const ink = Color(0xFF2B2A26);
  static const inkSoft = Color(0xFF55524A);
  static const muted = Color(0xFF8A8578);
  static const faint = Color(0xFFBDB6A6);
  static const track = Color(0xFFEDE6D8);

  // Leaf: primary
  static const leaf = Color(0xFF58B85C);
  static const leafLip = Color(0xFF3F8F43);
  static const leafTint = Color(0xFFE5F3DC);
  static const leafDeep = Color(0xFF2F6E33);

  // Soil: browns, bin
  static const soil = Color(0xFF8B5E3C);
  static const soilLip = Color(0xFF6B4529);
  static const soilTint = Color(0xFFF1E5D8);
  static const soilDeep = Color(0xFF4E3220);

  // Sky: moisture
  static const sky = Color(0xFF4FB3E8);
  static const skyLip = Color(0xFF2E8EC2);
  static const skyTint = Color(0xFFE1F2FB);

  // Sun: XP
  static const sun = Color(0xFFFFC83D);
  static const sunLip = Color(0xFFE0A21A);
  static const sunTint = Color(0xFFFFF4D6);

  // Flame: streak
  static const flame = Color(0xFFFF8A1F);
  static const flameLip = Color(0xFFDB6A05);
  static const flameTint = Color(0xFFFFEBD8);

  // Coral: warnings / avoid
  static const coral = Color(0xFFFF6B5E);
  static const coralLip = Color(0xFFD94A3E);
  static const coralTint = Color(0xFFFFE6E2);

  // Moss: leagues / teal accents
  static const moss = Color(0xFF2FAE9B);
  static const mossLip = Color(0xFF1F8676);
  static const mossTint = Color(0xFFDDF3EF);

  // Wren the worm
  static const worm = Color(0xFFF4A7A0);
  static const wormShade = Color(0xFFE48880);
  static const wormRing = Color(0xFFF9C6C0);
  static const wormCheek = Color(0xFFFF8A8A);

  // Illustration greens
  static const grass = Color(0xFFBFE3A5);
  static const grassDeep = Color(0xFF9DD07E);
  static const stem = Color(0xFF4E9A45);
  static const petalPink = Color(0xFFFF9EB5);
}

/// A face/lip/tint trio for chunky, tinted components.
class Tone {
  const Tone(this.face, this.lip, this.tint);
  final Color face;
  final Color lip;
  final Color tint;

  static const leaf = Tone(C.leaf, C.leafLip, C.leafTint);
  static const soil = Tone(C.soil, C.soilLip, C.soilTint);
  static const sky = Tone(C.sky, C.skyLip, C.skyTint);
  static const sun = Tone(C.sun, C.sunLip, C.sunTint);
  static const flame = Tone(C.flame, C.flameLip, C.flameTint);
  static const coral = Tone(C.coral, C.coralLip, C.coralTint);
  static const moss = Tone(C.moss, C.mossLip, C.mossTint);
}

/// Spacing on a 4/8 grid.
abstract final class S {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const gutter = 16.0;
}

/// Corner radii.
abstract final class R {
  static const chip = 12.0;
  static const button = 16.0;
  static const card = 24.0;
  static const sheet = 32.0;
}

/// Motion timings.
abstract final class M {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 450);
  static const stagger = Duration(milliseconds: 40);
}
