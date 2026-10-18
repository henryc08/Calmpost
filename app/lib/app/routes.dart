import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../domain/drop.dart';
import '../features/photo/photo_screen.dart';
import '../features/history/drop_history_screen.dart';
import '../features/calibration/calibration_screen.dart';
import '../features/connection/bin_connection_screen.dart';

import '../features/drop/drop_sheet.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/greenhouse/greenhouse_screen.dart';
import '../features/social/social_screen.dart';
import '../features/levels/level_map.dart';
import '../features/greenhouse/collectible_details.dart';
import '../data/collectibles.dart';
import '../features/trunc/trunc_screen.dart';

/// Cross-feature navigation, so features never import each other.
abstract final class Routes {
  static Future<void> connectBin(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BinConnectionScreen()));
  static Future<void> calibration(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CalibrationScreen()));
  static Future<void> dropHistory(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DropHistoryScreen()));
  static Future<void> photo(BuildContext context, {Uint8List? recovered}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoScreen(recovered: recovered)));
  static Future<void> review(BuildContext context, Drop drop) => showDropSheet(context, initialDrop: drop);
  static Future<void> trunc(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TruncScreen()));
  static Future<void> levels(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LevelMapScreen()));
  static Future<void> seed(BuildContext context, String id) => showCollectibleDetails(context, collectibleById[id]!);
  static Future<void> inventory(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InventoryScreen()));

  /// Camera drop-in: arm the camera, then review what it saw.
  static Future<void> drop(BuildContext context) => showDropSheet(context);

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
}
