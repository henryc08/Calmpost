import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'type.dart';

/// The signature green band with a two-layer hill along its bottom edge.
/// Every main tab opens with one. Content on it is white.
class BrandBand extends StatelessWidget {
  const BrandBand({super.key, required this.child, this.bottomPadding = 54});
  final Widget child;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _BandPainter(),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: child,
      ),
    );
  }
}

class _BandPainter extends CustomPainter {
  const _BandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final back = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - 30)
      ..quadraticBezierTo(w * 0.78, h - 2, w * 0.52, h - 14)
      ..quadraticBezierTo(w * 0.22, h - 28, 0, h - 6)
      ..close();
    canvas.drawPath(back, Paint()..color = C.brandDeep);
    final front = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - 40)
      ..quadraticBezierTo(w * 0.7, h - 8, w * 0.38, h - 26)
      ..quadraticBezierTo(w * 0.15, h - 38, 0, h - 22)
      ..close();
    canvas.drawPath(front, Paint()..color = C.brand);
  }

  @override
  bool shouldRepaint(_BandPainter old) => false;
}

/// A tab page: brand band header (title, subtitle, optional trailing and hero)
/// followed by open sections on the paper. Light status-bar icons over the band.
class BrandPage extends StatelessWidget {
  const BrandPage({super.key, required this.title, this.subtitle, this.trailing, this.hero, required this.children, this.controller});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Optional content under the title, still on the green band.
  final Widget? hero;
  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.only(bottom: S.x8),
        children: [
          BrandBand(
            child: Padding(
              padding: EdgeInsets.fromLTRB(S.gutter, top + S.x4, S.gutter, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: T.display.copyWith(color: C.onBrand)),
                            if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: T.label.copyWith(color: C.onBrandMuted))],
                          ],
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  if (hero != null) ...[const SizedBox(height: S.x5), hero!],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}

/// Caps section label with an optional trailing widget, used on the paper.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(text, style: T.caps)),
        ?trailing,
      ],
    );
  }
}

/// Spacing + hairline between open sections.
class SectionBreak extends StatelessWidget {
  const SectionBreak({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: S.x6),
      child: SizedBox(height: 1, child: ColoredBox(color: C.line)),
    );
  }
}

/// Pink pill for XP and rewards (dark text on pink, never pink text on green).
class PinkPill extends StatelessWidget {
  const PinkPill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: C.pink, borderRadius: BorderRadius.circular(R.pill)),
      child: Text(text, style: T.num.copyWith(fontSize: 11.5, color: C.ink)),
    );
  }
}

/// Segmented control drawn on the green band (white pill for the selected item).
class BandSegments<V> extends StatelessWidget {
  const BandSegments({super.key, required this.values, required this.selected, required this.label, required this.onChanged});
  final List<V> values;
  final V selected;
  final String Function(V) label;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.brandDeep, borderRadius: BorderRadius.circular(R.pill)),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (v != selected) HapticFeedback.selectionClick();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: M.base,
                  curve: M.ease,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(color: v == selected ? C.onBrand : Colors.transparent, borderRadius: BorderRadius.circular(R.pill)),
                  alignment: Alignment.center,
                  child: Text(
                    label(v),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.small.copyWith(fontSize: 13, color: v == selected ? C.brandDeep : C.onBrand, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Segmented control on the paper.
class PaperSegments<V> extends StatelessWidget {
  const PaperSegments({super.key, required this.values, required this.selected, required this.label, required this.onChanged});
  final List<V> values;
  final V selected;
  final String Function(V) label;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: C.sunk, borderRadius: BorderRadius.circular(R.pill)),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (v != selected) HapticFeedback.selectionClick();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: M.base,
                  curve: M.ease,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: v == selected ? C.surface : Colors.transparent, borderRadius: BorderRadius.circular(R.pill)),
                  alignment: Alignment.center,
                  child: Text(
                    label(v),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.small.copyWith(fontSize: 12.5, color: v == selected ? C.ink : C.muted, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Initials avatar.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 36, this.highlight = false, this.onBrand = false});
  final String name;
  final double size;
  final bool highlight;
  final bool onBrand;

  static const _tints = [Color(0xFFCFE6C6), Color(0xFFF3D9C4), Color(0xFFD3E2F0), Color(0xFFF0D3E4), Color(0xFFE6E2C2), Color(0xFFD7D3EC)];

  String get _initials {
    final parts = name.replaceAll(RegExp(r'[^A-Za-z ]'), ' ').trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts.first[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = onBrand ? C.onBrand : (highlight ? C.pink : _tints[name.hashCode.abs() % _tints.length]);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: T.num.copyWith(fontSize: size * 0.36, color: onBrand ? C.brandDeep : C.ink),
      ),
    );
  }
}
