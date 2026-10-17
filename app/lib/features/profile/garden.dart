import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models.dart';
import '../../ui/ui.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Flora-style garden: a meadow where every healthy day grew a plant.
class GardenField extends StatelessWidget {
  const GardenField({super.key, required this.plants});
  final List<GardenPlant> plants;

  @override
  Widget build(BuildContext context) {
    final shown = plants.reversed.take(20).toList().reversed.toList();
    return Container(
      decoration: BoxDecoration(color: C.grassDeep, borderRadius: BorderRadius.circular(R.card)),
      padding: const EdgeInsets.only(bottom: 5),
      child: Container(
        decoration: BoxDecoration(color: C.grass, borderRadius: BorderRadius.circular(R.card)),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _MeadowPainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.x2, S.x3, S.x2, S.x2),
            child: GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.88,
              children: [
                for (final (i, p) in shown.indexed)
                  Pressable(
                    onTap: () => _info(context, p),
                    child: Transform.translate(
                      offset: Offset(0, (i % 5).isOdd ? 6 : 0),
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Plant(p.species, size: 66, wilted: p.wilted),
                          if (p.rare) const Positioned(top: 0, right: 4, child: Icon(PhosphorIconsFill.sparkle, color: C.sun, size: 16)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _info(BuildContext context, GardenPlant p) {
    showCalmSheet<void>(
      context,
      builder: (context) {
        return Column(
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(color: p.wilted ? C.bgDeep : C.leafTint, shape: BoxShape.circle),
              child: Plant(p.species, size: 150, wilted: p.wilted, grow: true),
            ),
            const SizedBox(height: S.x3),
            Text(speciesName(p.species), style: T.h1),
            const SizedBox(height: S.x1),
            Text('${_months[p.day.month - 1]} ${p.day.day}', style: T.small),
            const SizedBox(height: S.x3),
            Text(
              p.rare
                  ? 'A rare plant, grown from a compost harvest.'
                  : p.wilted
                  ? 'Wilted: the bin was out of balance that day. Keep it healthy and new plants will grow.'
                  : 'Grown on a healthy bin day.',
              textAlign: TextAlign.center,
              style: T.body,
            ),
          ],
        );
      },
    );
  }
}

class _MeadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final tuft = Paint()
      ..color = C.grassDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 40; i++) {
      final x = (i * 97 % 1000) / 1000 * size.width;
      final y = (i * 61 % 1000) / 1000 * size.height;
      canvas.drawLine(Offset(x, y), Offset(x - 3, y - 6), tuft);
      canvas.drawLine(Offset(x, y), Offset(x + 3, y - 6), tuft);
    }
    // Soft hill bands like Flora's garden.
    final hill = Paint()..color = C.grassDeep.withValues(alpha: 0.35);
    canvas.drawOval(Rect.fromLTWH(-size.width * 0.2, size.height * 0.82, size.width * 0.8, size.height * 0.4), hill);
    canvas.drawOval(Rect.fromLTWH(size.width * 0.45, size.height * 0.86, size.width * 0.8, size.height * 0.4), hill);
  }

  @override
  bool shouldRepaint(_MeadowPainter old) => false;
}
