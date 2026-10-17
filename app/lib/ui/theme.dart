import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.leaf, primary: C.leaf, surface: C.bg, onSurface: C.ink, error: C.coral);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    fontFamily: 'Nunito',
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    textTheme: const TextTheme(
      displayLarge: T.display,
      headlineMedium: T.h1,
      titleLarge: T.h2,
      titleMedium: T.title,
      bodyLarge: T.body,
      bodyMedium: T.body,
      labelLarge: T.label,
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: C.leaf, selectionColor: C.leafTint, selectionHandleColor: C.leaf),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()}),
  );
}
