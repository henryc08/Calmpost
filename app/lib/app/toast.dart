import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../data/mock_repository.dart';
import '../state/celebrations.dart';
import '../state/providers.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import '../ui/type.dart';

void showToast(WidgetRef ref, String message, {int xp = 0}) => ref.read(toastProvider.notifier).show(message, xp: xp);

/// Quiet toast that drops in from the top.
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
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 2200), () => ref.read(toastProvider.notifier).clear(next.id));
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
              child: toast == null
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : Container(
                      key: ValueKey(toast.id),
                      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: 10),
                      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(R.pill)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (toast.xp > 0) ...[Text('+${toast.xp} XP', style: T.num.copyWith(color: C.sprout)), const SizedBox(width: S.x2)],
                          Flexible(
                            child: Text(toast.message, style: T.small.copyWith(color: Colors.white, fontSize: 13)),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.6, curve: M.ease),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hidden demo control (long-press the health card): pick what the mock bin reports.
Future<void> showScenarioPicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.hero))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x6, S.gutter, S.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Demo scenario', style: T.title),
            const SizedBox(height: S.x1),
            Text('Switch what the mock sensors report.', style: T.body),
            const SizedBox(height: S.x4),
            for (final s in Scenario.values)
              Pressable(
                onTap: () {
                  ref.read(scenarioProvider.notifier).state = s;
                  Navigator.of(context).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x3),
                  child: Row(
                    children: [
                      Expanded(child: Text(s.label, style: T.heading)),
                      if (ref.read(scenarioProvider) == s) const Icon(PhosphorIconsBold.check, size: 18, color: C.leaf),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Placeholder for tabs that haven't been redesigned yet.
class ComingNext extends StatelessWidget {
  const ComingNext(this.title, this.description, {super.key});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(S.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: S.x4),
            Text(title, style: T.display),
            const Spacer(),
            Center(
              child: Column(
                children: [
                  const Icon(PhosphorIconsRegular.compassTool, size: 28, color: C.faint),
                  const SizedBox(height: S.x3),
                  Text('Designing next', style: T.heading.copyWith(color: C.muted)),
                  const SizedBox(height: S.x1),
                  Text(description, textAlign: TextAlign.center, style: T.small),
                ],
              ),
            ),
            const Spacer(flex: 2),
            const Hairline(),
          ],
        ),
      ),
    );
  }
}
