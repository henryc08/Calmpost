import 'package:flutter/material.dart';

import '../features/greenhouse/greenhouse_screen.dart';

/// Cross-feature navigation, so features never import each other.
abstract final class Routes {
  /// The Greenhouse (Seed Packet gacha, collection, what Loam is for).
  static Future<void> greenhouse(BuildContext context) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, a, b) => const GreenhouseScreen(),
      transitionsBuilder: (context, a, b, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: const Cubic(0.2, 0.8, 0.2, 1))),
        child: child,
      ),
    ),
  );
}
