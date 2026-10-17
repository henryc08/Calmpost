import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Type scale. Nunito, weights 600–900 only.
abstract final class T {
  static const _f = 'Nunito';
  static const _tab = [FontFeature.tabularFigures()];

  static const display = TextStyle(fontFamily: _f, fontSize: 34, height: 1.1, fontWeight: FontWeight.w900, color: C.ink, letterSpacing: -0.5);
  static const h1 = TextStyle(fontFamily: _f, fontSize: 28, height: 1.15, fontWeight: FontWeight.w900, color: C.ink, letterSpacing: -0.3);
  static const h2 = TextStyle(fontFamily: _f, fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: C.ink);
  static const title = TextStyle(fontFamily: _f, fontSize: 17, height: 1.25, fontWeight: FontWeight.w800, color: C.ink);
  static const body = TextStyle(fontFamily: _f, fontSize: 15, height: 1.4, fontWeight: FontWeight.w600, color: C.inkSoft);
  static const bodyStrong = TextStyle(fontFamily: _f, fontSize: 15, height: 1.4, fontWeight: FontWeight.w800, color: C.ink);
  static const small = TextStyle(fontFamily: _f, fontSize: 13, height: 1.35, fontWeight: FontWeight.w700, color: C.muted);

  /// Duolingo-style caps label for buttons and eyebrows.
  static const label = TextStyle(fontFamily: _f, fontSize: 15, height: 1, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: C.ink);
  static const eyebrow = TextStyle(fontFamily: _f, fontSize: 12, height: 1, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: C.muted);

  /// Numbers: tabular so count-ups don't jitter.
  static const numXL = TextStyle(fontFamily: _f, fontSize: 44, height: 1, fontWeight: FontWeight.w900, color: C.ink, fontFeatures: _tab, letterSpacing: -1);
  static const numL = TextStyle(fontFamily: _f, fontSize: 28, height: 1, fontWeight: FontWeight.w900, color: C.ink, fontFeatures: _tab);
  static const numM = TextStyle(fontFamily: _f, fontSize: 17, height: 1, fontWeight: FontWeight.w900, color: C.ink, fontFeatures: _tab);
}
