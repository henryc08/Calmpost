import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.forest, primary: C.forest, surface: C.paper, onSurface: C.ink, error: C.clay),
    scaffoldBackgroundColor: C.paper,
    fontFamily: 'Manrope',
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    textTheme: const TextTheme(bodyMedium: T.body, bodyLarge: T.body, titleMedium: T.heading),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: C.forest, selectionColor: C.leafSoft, selectionHandleColor: C.forest),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()}),
  );
}
