import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/health_score.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Three compact readings (top, bottom, air) with a 24 h sparkline each.
class LayerStrip extends StatelessWidget {
  const LayerStrip({super.key, required this.s, required this.onOpen});
  final BinSnapshot s;
  final ValueChanged<Zone> onOpen;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Tile(zone: Zone.top, s: s, onTap: () => onOpen(Zone.top)),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: _Tile(zone: Zone.bottom, s: s, onTap: () => onOpen(Zone.bottom)),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: _Tile(zone: Zone.air, s: s, onTap: () => onOpen(Zone.air)),
          ),
        ],
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.zone, required this.s, required this.onTap});
  final Zone zone;
  final BinSnapshot s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metric = zone == Zone.air ? Metric.co2 : Metric.moisture;
    final trend = ref.watch(trendProvider((zone, metric))).valueOrNull;

    final (label, value, unit, sub) = switch (zone) {
      Zone.top => ('Top', '${s.topMoisture.round()}', '%', '${s.topTemp.round()}°C'),
      Zone.bottom => ('Bottom', '${s.bottomMoisture.round()}', '%', '${s.bottomTemp.round()}°C'),
      Zone.air => ('Air', s.co2 >= 1000 ? (s.co2 / 1000).toStringAsFixed(1) : '${s.co2.round()}', s.co2 >= 1000 ? 'k' : '', 'CO₂ ppm'),
    };
    final state = zoneState(s, zone);
    final (dot, note) = switch (state) {
      ZoneState.wet => (C.water, 'Wet'),
      ZoneState.dry => (C.amber, 'Dry'),
      ZoneState.hot => (C.clay, 'High'),
      _ => (C.leaf, 'Good'),
    };

    return Panel(
      onTap: onTap,
      radius: R.tile + 2,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: T.small.copyWith(color: C.ink2)),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(note, style: T.small.copyWith(fontSize: 11, color: dot)),
            ],
          ),
          const SizedBox(height: S.x3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: T.value),
                Text(unit, style: T.label.copyWith(color: C.ink2)),
              ],
            ),
          ),
          Text(sub, style: T.small.copyWith(fontSize: 11.5)),
          const SizedBox(height: S.x3),
          Sparkline(
            values: trend?.map((p) => p.value).toList() ?? const [],
            color: zone == Zone.air ? C.ink2 : (state == ZoneState.good ? C.leaf : dot),
            band: zone == Zone.air ? null : (moistureLo, moistureHi),
            height: 26,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('24h', style: T.small.copyWith(fontSize: 10.5, color: C.faint)),
              const Spacer(),
              const Icon(PhosphorIconsRegular.arrowUpRight, size: 13, color: C.faint),
            ],
          ),
        ],
      ),
    );
  }
}
