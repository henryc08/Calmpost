import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../sfx.dart';
import '../tokens.dart';
import 'buttons.dart';

class TabItem {
  const TabItem(this.icon, this.tone, this.label);
  final IconData icon;
  final Tone tone;
  final String label;
}

/// Bottom navigation: four tabs around a raised centre "log a scrap" button.
class TabBarCalm extends StatelessWidget {
  const TabBarCalm({super.key, required this.items, required this.index, required this.onTap, required this.onCenter});
  final List<TabItem> items; // exactly 4
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget tab(int i) => Expanded(
      child: _Tab(item: items[i], active: i == index, onTap: () => onTap(i)),
    );
    return Container(
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(top: BorderSide(color: C.border, width: 2)),
      ),
      padding: EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, S.x2 + bottom),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            tab(0),
            tab(1),
            SizedBox(
              width: 84,
              child: OverflowBox(
                maxHeight: 100,
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Semantics(
                    button: true,
                    label: 'Log a scrap',
                    child: ChunkyCircle(
                      size: 68,
                      lipHeight: 6,
                      ring: Colors.white,
                      onPressed: onCenter,
                      child: const Icon(PhosphorIconsBold.plus, color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ),
            ),
            tab(2),
            tab(3),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.active, required this.onTap});
  final TabItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!active) Sfx.tap();
          onTap();
        },
        child: Center(
          child: AnimatedContainer(
            duration: M.base,
            curve: Curves.easeOut,
            width: 56,
            height: 48,
            decoration: BoxDecoration(
              color: active ? item.tone.tint : Colors.transparent,
              borderRadius: BorderRadius.circular(R.button),
              border: Border.all(color: active ? item.tone.face.withValues(alpha: 0.55) : Colors.transparent, width: 2),
            ),
            child: AnimatedScale(
              scale: active ? 1.08 : 1,
              duration: M.base,
              curve: Curves.easeOutBack,
              child: Icon(item.icon, size: 28, color: active ? item.tone.face : C.faint),
            ),
          ),
        ),
      ),
    );
  }
}
