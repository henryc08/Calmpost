import 'package:flutter/material.dart';

import '../features/greenhouse/greenhouse_screen.dart';
import '../features/rewards/rewards_screen.dart';
import '../features/social/social_screen.dart';

/// Cross-feature navigation, so features never import each other.
abstract final class Routes {
  static void socialProfile(BuildContext context, String id) => openSocial(context, PersonScreen(id: id));
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

  /// Rewards inbox (the gift on Home): crates and Seed Packets to open, plus history.
  static Future<void> rewards(BuildContext context) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, a, b) => const RewardsScreen(openGreenhouse: greenhouse),
      transitionsBuilder: (context, a, b, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: const Cubic(0.2, 0.8, 0.2, 1))),
        child: child,
      ),
    ),
  );
}
