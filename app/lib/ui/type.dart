import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Type scale. Fraunces (soft serif) for headline numbers and titles,
/// Manrope for everything else.
abstract final class T {
  static const _serif = 'Fraunces';
  static const _sans = 'Manrope';
  static const _tab = [FontFeature.tabularFigures()];

  // Serif
  static const hero = TextStyle(fontFamily: _serif, fontSize: 84, height: 0.95, fontWeight: FontWeight.w400, color: C.ink, letterSpacing: -3);
  static const display = TextStyle(fontFamily: _serif, fontSize: 32, height: 1.1, fontWeight: FontWeight.w400, color: C.ink, letterSpacing: -0.8);
  static const title = TextStyle(fontFamily: _serif, fontSize: 23, height: 1.15, fontWeight: FontWeight.w500, color: C.ink, letterSpacing: -0.4);
  static const stat = TextStyle(fontFamily: _serif, fontSize: 24, height: 1.1, fontWeight: FontWeight.w500, color: C.ink, letterSpacing: -0.5);

  // Sans
  static const heading = TextStyle(fontFamily: _sans, fontSize: 16, height: 1.3, fontWeight: FontWeight.w700, color: C.ink, letterSpacing: -0.1);
  static const body = TextStyle(fontFamily: _sans, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w500, color: C.ink2);
  static const label = TextStyle(fontFamily: _sans, fontSize: 13, height: 1.3, fontWeight: FontWeight.w600, color: C.muted);
  static const small = TextStyle(fontFamily: _sans, fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: C.muted);
  static const caps = TextStyle(fontFamily: _sans, fontSize: 11, height: 1.2, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: 1.2);
  static const button = TextStyle(fontFamily: _sans, fontSize: 14.5, height: 1.2, fontWeight: FontWeight.w700, color: C.ink);

  // Numbers
  static const value = TextStyle(
    fontFamily: _sans,
    fontSize: 22,
    height: 1.1,
    fontWeight: FontWeight.w700,
    color: C.ink,
    fontFeatures: _tab,
    letterSpacing: -0.5,
  );
  static const num = TextStyle(fontFamily: _sans, fontSize: 13, height: 1.2, fontWeight: FontWeight.w700, color: C.ink, fontFeatures: _tab);
}
