import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../features/debug/debug_sheet.dart';
import '../features/home/health_sheet.dart';
import '../features/layer/layer_screen.dart';
import '../features/log/log_screen.dart';
import '../features/shop/shop_sheet.dart';
import '../features/streak/streak_sheet.dart';
import '../ui/ui.dart';

/// Cross-feature navigation lives here so features never import each other.
abstract final class Routes {
  static Future<void> log(BuildContext context, {FoodItem? item}) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, a, b) => LogScreen(initial: item),
      transitionsBuilder: (context, a, b, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    ),
  );

  static Future<void> layer(BuildContext context, Zone zone) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LayerScreen(zone)));

  static Future<void> debug(BuildContext context) => showCalmSheet<void>(context, builder: (_) => const DebugSheet());

  static Future<void> health(BuildContext context) => showCalmSheet<void>(context, builder: (_) => const HealthSheet());

  static Future<void> streak(BuildContext context) => showCalmSheet<void>(context, builder: (_) => const StreakSheet());

  static Future<void> shop(BuildContext context) => showCalmSheet<void>(context, builder: (_) => const ShopSheet());
}
