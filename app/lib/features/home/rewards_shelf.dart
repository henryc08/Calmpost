import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/reward_reveal.dart';
import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../state/game.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Crates and Seed Packets waiting to be opened, front and centre.
class RewardsShelf extends ConsumerWidget {
  const RewardsShelf({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crates = ref.watch(gameProvider.select((g) => g.crates));
    final packets = ref.watch(gameProvider.select((g) => g.packets));
    if (crates.isEmpty && packets == 0) return const SizedBox.shrink();

    Future<void> open(int i) async {
      final o = await ref.read(gameProvider.notifier).openCrateAsync(i);
      if (o != null && context.mounted) await revealCrate(context, o.tier, o.loam, o.packets);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('REWARDS READY', trailing: PinkPill('${crates.length + packets} to open')),
        const SizedBox(height: S.x4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (i, c) in crates.indexed) ...[
                _Box(
                  icon: PhosphorIconsFill.package,
                  title: crateTitle(c).split(' ').first,
                  sub: 'Crate',
                  big: c != CrateTier.sprout,
                  delay: i * 400,
                  onTap: () => open(i),
                ),
                const SizedBox(width: S.x5),
              ],
              if (packets > 0)
                _Box(
                  icon: PhosphorIconsFill.plant,
                  title: '$packets',
                  sub: packets == 1 ? 'Seed Packet' : 'Seed Packets',
                  big: false,
                  delay: crates.length * 400,
                  onTap: () => Routes.greenhouse(context),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.icon, required this.title, required this.sub, required this.big, required this.delay, required this.onTap});
  final IconData icon;
  final String title;
  final String sub;
  final bool big;
  final int delay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = big ? 72.0 : 64.0;
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: C.surface,
              shape: BoxShape.circle,
              border: Border.all(color: C.pink, width: 2),
            ),
            child: Icon(icon, size: size * 0.42, color: C.pinkDeep),
          ).animate(onPlay: (c) => c.repeat(), delay: delay.ms).shake(hz: 5, rotation: 0.05, offset: Offset.zero, duration: 600.ms).then(delay: 2400.ms),
          const SizedBox(height: S.x2),
          Text(title, style: T.heading.copyWith(fontSize: 13.5)),
          Text(sub, style: T.small.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
