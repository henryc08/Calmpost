import 'package:flutter/material.dart';

import '../sfx.dart';
import '../tokens.dart';
import '../type.dart';

/// Squishes slightly on press. Base for anything tappable that isn't a ChunkyButton.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.96, this.sound = true});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool sound;

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
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.sound) Sfx.tap();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(scale: _down ? widget.scale : 1, duration: M.fast, curve: Curves.easeOut, child: widget.child),
    );
  }
}

enum ChunkyVariant { primary, sun, sky, coral, flame, moss, soil, white, ghost }

class _ChunkyColors {
  const _ChunkyColors(this.face, this.lip, this.text, {this.border});
  final Color face;
  final Color lip;
  final Color text;
  final Color? border;
}

_ChunkyColors _colorsFor(ChunkyVariant v) => switch (v) {
  ChunkyVariant.primary => const _ChunkyColors(C.leaf, C.leafLip, Colors.white),
  ChunkyVariant.sun => const _ChunkyColors(C.sun, C.sunLip, C.soilDeep),
  ChunkyVariant.sky => const _ChunkyColors(C.sky, C.skyLip, Colors.white),
  ChunkyVariant.coral => const _ChunkyColors(C.coral, C.coralLip, Colors.white),
  ChunkyVariant.flame => const _ChunkyColors(C.flame, C.flameLip, Colors.white),
  ChunkyVariant.moss => const _ChunkyColors(C.moss, C.mossLip, Colors.white),
  ChunkyVariant.soil => const _ChunkyColors(C.soil, C.soilLip, Colors.white),
  ChunkyVariant.white => const _ChunkyColors(C.surface, C.borderDark, C.inkSoft, border: C.borderDark),
  ChunkyVariant.ghost => const _ChunkyColors(Colors.transparent, Colors.transparent, C.leafLip),
};

/// The Duolingo button: solid face over a darker lip. Pressing pushes the face
/// down into the lip.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ChunkyVariant.primary,
    this.icon,
    this.expand = true,
    this.height = 52,
    this.radius = R.button,
    this.uppercase = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final ChunkyVariant variant;
  final IconData? icon;
  final bool expand;
  final double height;
  final double radius;
  final bool uppercase;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;
  static const _lip = 4.0;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final c = disabled ? const _ChunkyColors(C.track, C.borderDark, C.faint) : _colorsFor(widget.variant);
    final pressed = _down && !disabled;
    final ghost = widget.variant == ChunkyVariant.ghost;
    final lip = ghost ? 0.0 : _lip;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[Icon(widget.icon, color: c.text, size: 20), if (widget.label.isNotEmpty) const SizedBox(width: S.x2)],
        if (widget.label.isNotEmpty)
          Flexible(
            child: Text(
              widget.uppercase ? widget.label.toUpperCase() : widget.label,
              style: T.label.copyWith(color: c.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: disabled ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: disabled
          ? null
          : () {
              Sfx.tap();
              widget.onPressed!();
            },
      child: SizedBox(
        height: widget.height + lip,
        child: Stack(
          children: [
            Positioned.fill(
              top: lip,
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.lip, borderRadius: BorderRadius.circular(widget.radius)),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 70),
              left: 0,
              right: 0,
              top: pressed ? lip : 0,
              height: widget.height,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: S.x5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.face,
                  borderRadius: BorderRadius.circular(widget.radius),
                  border: c.border != null ? Border.all(color: c.border!, width: 2) : null,
                ),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );

    return widget.expand ? SizedBox(width: double.infinity, child: button) : IntrinsicWidth(child: button);
  }
}

/// Round chunky icon button (the centre Log button, map nodes, etc).
class ChunkyCircle extends StatefulWidget {
  const ChunkyCircle({
    super.key,
    required this.child,
    required this.onPressed,
    this.size = 64,
    this.face = C.leaf,
    this.lip = C.leafLip,
    this.lipHeight = 5,
    this.ring,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double size;
  final Color face;
  final Color lip;
  final double lipHeight;
  final Color? ring;

  @override
  State<ChunkyCircle> createState() => _ChunkyCircleState();
}

class _ChunkyCircleState extends State<ChunkyCircle> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.lipHeight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onPressed == null
          ? null
          : () {
              Sfx.tap();
              widget.onPressed!();
            },
      child: SizedBox(
        width: widget.size,
        height: widget.size * 0.92 + l,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: l,
              height: widget.size * 0.92,
              child: DecoratedBox(
                decoration: BoxDecoration(color: widget.lip, borderRadius: BorderRadius.all(Radius.elliptical(widget.size, widget.size * 0.92))),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 70),
              left: 0,
              right: 0,
              top: _down ? l : 0,
              height: widget.size * 0.92,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.face,
                  borderRadius: BorderRadius.all(Radius.elliptical(widget.size, widget.size * 0.92)),
                  border: widget.ring != null ? Border.all(color: widget.ring!, width: 3) : null,
                ),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
