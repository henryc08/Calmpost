import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Metric shortcuts. Moisture keeps both points visible, never an average.
class ReadingsRow extends StatelessWidget {
  const ReadingsRow({super.key, required this.s, required this.onOpen});
  final BinSnapshot s;
  final ValueChanged<Metric> onOpen;

  @override
  Widget build(BuildContext context) {
    Widget col(Metric metric, String label, String value, String sub) => Expanded(
      child: Semantics(
        button: true,
        label: 'Open $label readings: $value, $sub',
        child: Pressable(
          onTap: () => onOpen(metric),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x2, horizontal: 4),
            child: Column(
              children: [
                Text(label, style: T.caps.copyWith(fontSize: 10)),
                const SizedBox(height: S.x2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: T.value.copyWith(fontSize: 23)),
                ),
                const SizedBox(height: 3),
                Text(sub, textAlign: TextAlign.center, style: T.small.copyWith(fontSize: 10.5)),
              ],
            ),
          ),
        ),
      ),
    );
    return IntrinsicHeight(
      child: Row(
        children: [
          col(
            Metric.moisture,
            'MOISTURE',
            '${s.topMeasured ? '${s.topMoisture.round()}%' : '—'} / ${s.bottomMeasured ? '${s.bottomMoisture.round()}%' : '—'}',
            s.readingsStale ? 'Last readings' : 'Probe 1 / Probe 2',
          ),
          const Hairline(vertical: true),
          col(
            Metric.temperature,
            'TEMP',
            s.topTemperatureMeasured ? '${s.topTemp.toStringAsFixed(1)}°C' : '—',
            !s.topTemperatureMeasured
                ? 'Not measured'
                : s.readingsStale
                ? 'Last reading'
                : 'Compost probe',
          ),
          const Hairline(vertical: true),
          col(
            Metric.co2,
            'CO₂',
            s.airMeasured ? '${s.co2.round()}' : '—',
            !s.airMeasured
                ? 'Not measured'
                : s.readingsStale
                ? 'ppm · last reading'
                : 'ppm · air',
          ),
        ],
      ),
    );
  }
}
