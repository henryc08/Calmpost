import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/drop.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// The camera's photo with a box around each thing it found. Without a photo
/// (Gemini failed before a thumbnail, or the mock), a quiet placeholder keeps
/// the boxes so the layout doesn't jump.
class DropPhoto extends StatelessWidget {
  const DropPhoto({super.key, required this.drop, this.height = 168});
  final Drop drop;
  final double height;

  @override
  Widget build(BuildContext context) {
    final thumb = drop.thumbnail;
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.tile),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb != null)
              Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true)
            else
              const ColoredBox(
                color: C.sunk,
                child: Center(child: Icon(PhosphorIconsRegular.camera, size: 30, color: C.faint)),
              ),
            CustomPaint(painter: _Boxes([for (final i in drop.items) if (i.box != null) i.box!])),
            Positioned(
              left: S.x2,
              bottom: S.x2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: C.ink.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(R.pill)),
                child: Text(thumb != null ? 'From the bin camera' : 'No photo', style: T.small.copyWith(color: Colors.white, fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Boxes extends CustomPainter {
  _Boxes(this.boxes);
  final List<List<double>> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = C.pink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final b in boxes) {
      if (b.length != 4) continue;
      final r = Rect.fromLTRB(b[1] / 1000 * size.width, b[0] / 1000 * size.height, b[3] / 1000 * size.width, b[2] / 1000 * size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), stroke);
    }
  }

  @override
  bool shouldRepaint(_Boxes old) => old.boxes != boxes;
}
