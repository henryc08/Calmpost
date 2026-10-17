import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/gacha.dart';
import '../../domain/models.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// A collectible as a round badge with a rarity ring.
class CollectibleBadge extends StatelessWidget {
  const CollectibleBadge({super.key, required this.item, this.size = 64});
  final Collectible item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ring = rarityColor(item.rarity);
    final Widget inner = switch (item.type) {
      // Finishes preview the ring itself.
      CollectibleType.finish => Container(
        width: size * 0.56,
        height: size * 0.56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: item.color, width: size * 0.09),
          color: C.brand,
        ),
      ),
      CollectibleType.title => Icon(item.icon, size: size * 0.42, color: item.color),
      CollectibleType.specimen => Icon(item.icon, size: size * 0.5, color: item.color),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: item.type == CollectibleType.finish ? C.surface : ring.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: size > 80 ? 3 : 2),
      ),
      child: Center(child: inner),
    );
  }
}

/// An unowned slot: a faint ring in the rarity colour and a question mark.
class LockedBadge extends StatelessWidget {
  const LockedBadge({super.key, required this.rarity, this.size = 64});
  final Rarity rarity;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: C.sunk,
        shape: BoxShape.circle,
        border: Border.all(color: rarityColor(rarity).withValues(alpha: 0.45), width: 1.5),
      ),
      child: Icon(PhosphorIconsBold.question, size: size * 0.32, color: C.faint),
    );
  }
}

class RarityPill extends StatelessWidget {
  const RarityPill(this.rarity, {super.key, this.onDark = false});
  final Rarity rarity;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: onDark ? c : c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(R.pill)),
      child: Text(rarityName(rarity).toUpperCase(), style: T.caps.copyWith(fontSize: 10.5, color: onDark ? C.ink : c)),
    );
  }
}

/// The Seed Packet: a paper sachet with a zigzag top and a sprout.
class SeedPacketArt extends StatelessWidget {
  const SeedPacketArt({super.key, this.size = 100});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.8,
      height: size,
      child: CustomPaint(
        painter: _PacketPainter(),
        child: Padding(
          padding: EdgeInsets.only(top: size * 0.2),
          child: Column(
            children: [
              Icon(PhosphorIconsFill.plant, size: size * 0.32, color: C.brand),
              if (size >= 80) ...[
                SizedBox(height: size * 0.04),
                Text(
                  'SEEDS',
                  style: T.caps.copyWith(fontSize: size * 0.085, color: C.brandDeep),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PacketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final teeth = 7;
    final tooth = w / teeth;
    final path = Path()..moveTo(0, h * 0.1);
    for (var i = 0; i < teeth; i++) {
      path
        ..lineTo(tooth * i + tooth / 2, h * 0.04)
        ..lineTo(tooth * (i + 1), h * 0.1);
    }
    path
      ..lineTo(w, h * 0.94)
      ..quadraticBezierTo(w, h, w * 0.94, h)
      ..lineTo(w * 0.06, h)
      ..quadraticBezierTo(0, h, 0, h * 0.94)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFF8EC));
    // Pink band along the bottom.
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.78, w, h * 0.22), Paint()..color = C.pink);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.16, w, h * 0.02), Paint()..color = C.brand.withValues(alpha: 0.4));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PacketPainter old) => false;
}
