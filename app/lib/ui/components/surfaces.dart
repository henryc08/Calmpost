import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';

/// The card: white face, 2px border, thicker bottom edge. No shadows.
class Slab extends StatelessWidget {
  const Slab({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.x4),
    this.color = C.surface,
    this.edge = C.border,
    this.radius = R.card,
    this.onTap,
    this.lip = 4,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color edge;
  final double radius;
  final VoidCallback? onTap;
  final double lip;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(color: edge, borderRadius: BorderRadius.circular(radius)),
      padding: EdgeInsets.fromLTRB(2, 2, 2, lip),
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius - 2)),
        padding: padding,
        child: child,
      ),
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, scale: 0.98, child: card);
  }
}

/// Small rounded label with tinted fill.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = Tone.leaf, this.icon, this.dense = false});
  final String text;
  final Tone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(R.chip)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: dense ? 13 : 15, color: tone.lip), const SizedBox(width: 4)],
          Text(
            text,
            style: (dense ? T.small : T.small.copyWith(fontSize: 14)).copyWith(color: tone.lip, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Section heading with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.onTrailing});
  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Text(title, style: T.h2)),
          if (trailing != null)
            Pressable(
              onTap: onTrailing,
              child: Text(trailing!.toUpperCase(), style: T.eyebrow.copyWith(color: C.sky)),
            ),
        ],
      ),
    );
  }
}

/// Circular icon badge with a tinted background.
class IconBlob extends StatelessWidget {
  const IconBlob(this.icon, {super.key, this.tone = Tone.leaf, this.size = 44, this.iconSize});
  final IconData icon;
  final Tone tone;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(size * 0.36)),
      child: Icon(icon, color: tone.face, size: iconSize ?? size * 0.55),
    );
  }
}
