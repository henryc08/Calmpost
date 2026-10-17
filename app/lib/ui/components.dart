import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'tokens.dart';
import 'type.dart';

/// Gentle press feedback: a slight scale plus a selection haptic.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.98});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(scale: _down ? widget.scale : 1, duration: M.fast, curve: Curves.easeOut, child: widget.child),
    );
  }
}

/// The card: white, hairline border, generous radius. No shadows.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.x5),
    this.color = C.surface,
    this.border = C.line,
    this.radius = R.panel,
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color? border;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: child,
    );
    return onTap == null ? box : Pressable(onTap: onTap, child: box);
  }
}

/// Solid pill button. Forest by default.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onTap, this.icon, this.color = C.forest, this.textColor = C.onForest, this.dense = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        height: dense ? 34 : 46,
        padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 20),
        decoration: BoxDecoration(color: onTap == null ? C.sunk : color, borderRadius: BorderRadius.circular(R.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (dense ? T.small : T.button).copyWith(color: onTap == null ? C.faint : textColor, fontWeight: FontWeight.w700),
              ),
            ),
            if (icon != null) ...[const SizedBox(width: 6), Icon(icon, size: dense ? 14 : 16, color: onTap == null ? C.faint : textColor)],
          ],
        ),
      ),
    );
  }
}

/// Outline chip with an optional leading icon.
class Chip2 extends StatelessWidget {
  const Chip2(this.label, {super.key, this.icon, this.onTap, this.color = C.ink2});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: C.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 6)],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.small.copyWith(color: C.ink, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small tinted label.
class Badge2 extends StatelessWidget {
  const Badge2(this.label, {super.key, required this.color, required this.background, this.icon});
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(R.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Text(
            label,
            style: T.small.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

/// Thin animated progress bar.
class ThinBar extends StatelessWidget {
  const ThinBar({super.key, required this.value, this.color = C.leaf, this.track = C.sunk, this.height = 4});
  final double value;
  final Color color;
  final Color track;
  final double height;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: M.slow,
      curve: M.ease,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: track)),
              FractionallySizedBox(
                widthFactor: v,
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated integer.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, required this.style, this.from, this.duration = const Duration(milliseconds: 900)});
  final int value;
  final int? from;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: (from ?? value).toDouble(), end: value.toDouble()),
      duration: duration,
      curve: M.ease,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// Minimal line chart for 24 h trends.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color = C.ink2, this.height = 28, this.band});
  final List<double> values;
  final Color color;
  final double height;

  /// Optional healthy band (lo, hi) drawn as a faint fill.
  final (double, double)? band;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, color, band)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.band);
  final List<double> values;
  final Color color;
  final (double, double)? band;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if (band != null) {
      lo = math.min(lo, band!.$1);
      hi = math.max(hi, band!.$2);
    }
    final span = (hi - lo).abs() < 1e-6 ? 1.0 : hi - lo;
    double y(double v) => size.height - 2 - (v - lo) / span * (size.height - 4);
    if (band != null) {
      canvas.drawRect(Rect.fromLTRB(0, y(band!.$2), size.width, y(band!.$1)), Paint()..color = C.leaf.withValues(alpha: 0.08));
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      i == 0 ? path.moveTo(x, y(values[i])) : path.lineTo(x, y(values[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(size.width, y(values.last)), 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

/// Pulsing "live" dot.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color = C.sprout, this.size = 7});
  final Color color;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.6,
      height: s * 2.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: s + s * 1.6 * _c.value,
              height: s + s * 1.6 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
              ),
            ),
            Container(
              width: s,
              height: s,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Loam currency mark: a small forest coin with a sprout.
class LoamCoin extends StatelessWidget {
  const LoamCoin({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: C.loam, shape: BoxShape.circle),
      child: Icon(PhosphorIconsFill.plant, size: size * 0.62, color: const Color(0xFFF2E3D2)),
    );
  }
}

/// Section title with an optional quiet trailing label.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(title, style: T.title)),
        ?trailing,
      ],
    );
  }
}

/// Hairline divider.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = false, this.color = C.line});
  final bool vertical;
  final Color color;

  @override
  Widget build(BuildContext context) => vertical ? Container(width: 1, color: color) : Container(height: 1, color: color);
}
