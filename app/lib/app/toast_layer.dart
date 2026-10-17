import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../state/celebrations.dart';
import '../ui/ui.dart';

/// Drops small reward toasts in from the top ("+5 XP · Checked in on Wren").
class ToastLayer extends ConsumerStatefulWidget {
  const ToastLayer({super.key});

  @override
  ConsumerState<ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends ConsumerState<ToastLayer> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(toastProvider, (prev, next) {
      if (next == null) return;
      if (next.xp > 0) Sfx.play(Sound.xp, volume: 0.6);
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 2400), () => ref.read(toastProvider.notifier).clear(next.id));
    });
    final toast = ref.watch(toastProvider);
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: S.x2),
            child: AnimatedSwitcher(
              duration: M.base,
              child: toast == null ? const SizedBox(key: ValueKey('none')) : _ToastCard(toast, key: ValueKey(toast.id)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard(this.toast, {super.key});
  final Toast toast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(S.x3, S.x2, S.x4, S.x2),
      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(R.card)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (toast.xp > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: C.sun, borderRadius: BorderRadius.circular(R.chip)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsFill.lightning, size: 14, color: C.soilDeep),
                  const SizedBox(width: 2),
                  Text(
                    '+${toast.xp} XP',
                    style: T.small.copyWith(color: C.soilDeep, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(width: S.x2),
          ] else ...[
            const Icon(PhosphorIconsFill.sparkle, size: 18, color: C.sun),
            const SizedBox(width: S.x2),
          ],
          Flexible(
            child: Text(toast.message, style: T.bodyStrong.copyWith(color: Colors.white, fontSize: 14)),
          ),
        ],
      ),
    ).animate().slideY(begin: -1.2, duration: 380.ms, curve: Curves.easeOutBack).fadeIn(duration: 200.ms);
  }
}
