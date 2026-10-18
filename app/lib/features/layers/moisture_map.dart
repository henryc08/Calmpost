import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// Discrete sensor patches: never interpolate two readings into invented data.
class MoistureMap extends StatelessWidget {
  const MoistureMap({super.key, required this.snapshot});
  final BinSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    Widget point(String label, double? value) {
      final stale = snapshot.readingsStale;
      final (color, status) = switch (value) {
        null => (C.faint, 'Not measured'),
        _ when stale => (C.faint, 'Last reading · stale'),
        < 40 => (C.amber, 'Below guide'),
        > 60 => (C.water, 'Above guide'),
        _ => (C.leaf, 'Within guide'),
      };
      return Semantics(
        label: '$label: ${value == null ? 'not measured' : '${value.round()} percent, $status'}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.all(S.x3),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  border: Border.all(color: color, width: 2),
                ),
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                ),
              ),
              const SizedBox(width: S.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: T.label),
                    Text(value == null ? '—' : '${value.round()}%', style: T.value),
                    Text(status, style: T.small),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: C.line, width: 2),
            borderRadius: BorderRadius.circular(R.tile),
          ),
          child: Column(
            children: [
              point('Probe 1 · Upper', snapshot.topMeasured ? snapshot.topMoisture : null),
              const Divider(height: 1, color: C.line, indent: 16, endIndent: 16),
              point('Probe 2 · Lower', snapshot.bottomMeasured ? snapshot.bottomMoisture : null),
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final entry in [(C.amber, 'Below 40'), (C.leaf, '40–60'), (C.water, 'Above 60'), (C.faint, 'Unknown / stale')])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, color: entry.$1),
                  const SizedBox(width: 5),
                  Text(entry.$2, style: T.small),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
