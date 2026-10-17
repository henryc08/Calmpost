import 'package:flutter/material.dart';

import '../../domain/health_score.dart';
import '../../domain/models.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Top · bottom · air as three open columns divided by hairlines.
class ReadingsRow extends StatelessWidget {
  const ReadingsRow({super.key, required this.s, required this.onOpen});
  final BinSnapshot s;
  final ValueChanged<Zone> onOpen;

  @override
  Widget build(BuildContext context) {
    Widget col(Zone z, String label, String value, String unit, String sub) {
      final st = zoneState(s, z);
      final (dot, note) = switch (st) {
        ZoneState.wet => (C.water, 'wet'),
        ZoneState.dry => (C.amber, 'dry'),
        ZoneState.hot => (C.clay, 'high'),
        ZoneState.unknown => (C.faint, 'not measured'),
        _ => (C.leaf, 'good'),
      };
      return Expanded(
        child: Pressable(
          onTap: () => onOpen(z),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x2),
            child: Column(
              children: [
                Text(label, style: T.caps.copyWith(fontSize: 10.5)),
                const SizedBox(height: S.x2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(value, style: T.value),
                      Text(unit, style: T.label.copyWith(color: C.ink2)),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(sub.isEmpty ? note : '$sub · $note', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small.copyWith(fontSize: 11.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final co2k = s.co2 >= 1000;
    return IntrinsicHeight(
      child: Row(
        children: [
          col(
            Zone.top,
            'TOP',
            s.topMeasured ? '${s.topMoisture.round()}' : '—',
            s.topMeasured ? '%' : '',
            s.topTemperatureMeasured ? '${s.topTemp.round()}°' : '',
          ),
          const Hairline(vertical: true),
          s.bottomMeasured
              ? col(Zone.bottom, 'BOTTOM', '${s.bottomMoisture.round()}', '%', s.bottomTemperatureMeasured ? '${s.bottomTemp.round()}°' : '')
              : col(Zone.bottom, 'BOTTOM', '—', '', ''),
          const Hairline(vertical: true),
          col(
            Zone.air,
            'AIR',
            !s.airMeasured
                ? '—'
                : co2k
                ? (s.co2 / 1000).toStringAsFixed(1)
                : '${s.co2.round()}',
            s.airMeasured && co2k ? 'k' : '',
            'CO₂',
          ),
        ],
      ),
    );
  }
}
