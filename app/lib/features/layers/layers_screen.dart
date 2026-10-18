import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/health_score.dart';
import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import '../../ui/info_dot.dart';
import 'moisture_map.dart';

/// Metric-first sensor view. The internal Layers route stays stable for deep links
/// and check-in rewards; top/bottom remain storage identifiers, not navigation.
class LayersScreen extends ConsumerStatefulWidget {
  const LayersScreen({super.key});

  @override
  ConsumerState<LayersScreen> createState() => _LayersScreenState();
}

class _LayersScreenState extends ConsumerState<LayersScreen> {
  Zone _moistureProbe = Zone.top;

  @override
  Widget build(BuildContext context) {
    final reading = ref.watch(binProvider);
    final s = reading.valueOrNull;
    if (s == null) {
      return BrandPage(
        title: 'Sensors',
        children: [
          if (reading.hasError) ...[
            Text("Can't reach the bin.", style: T.heading),
            TextButton(
              onPressed: () => ref.invalidate(binProvider),
              child: Text('Retry readings', style: T.button),
            ),
          ] else ...[
            const Center(child: CircularProgressIndicator(color: C.forest)),
            const SizedBox(height: S.x3),
            Text('Waiting for sensor readings…', style: T.body),
          ],
        ],
      );
    }
    final metric = ref.watch(sensorMetricProvider);
    final zone = metric == Metric.moisture ? _moistureProbe : (metric == Metric.co2 ? Zone.air : Zone.top);
    final trendKey = (zone, metric);
    final trendState = ref.watch(trendProvider(trendKey));
    final trend = trendState.valueOrNull ?? const <TrendPoint>[];
    final logs = ref.watch(gameProvider.select((g) => g.logs));
    final measured = switch (metric) {
      Metric.moisture => zone == Zone.top ? s.topMeasured : s.bottomMeasured,
      Metric.temperature => s.topTemperatureMeasured,
      Metric.co2 => s.airMeasured,
    };
    final moisture = metric == Metric.moisture;
    final value = metric == Metric.temperature ? (measured ? '${s.topTemp.toStringAsFixed(1)} °C' : '—') : (measured ? '${s.co2.round()} ppm' : '—');

    return BrandPage(
      title: 'Sensors',
      subtitle: s.readingsStale ? 'Kitchen bin · last reading ${s.ageLabel(DateTime.now())}' : 'Kitchen bin · live',
      trailing: s.readingsStale ? null : const LiveDot(color: C.onBrand),
      hero: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Two primary hardware views; air readings remain reachable below.
          BandSegments<Metric>(
            values: const [Metric.moisture, Metric.temperature],
            selected: metric,
            label: (m) => m == Metric.moisture ? 'Moisture' : 'Temperature',
            onChanged: (m) => ref.read(sensorMetricProvider.notifier).state = m,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ref.read(sensorMetricProvider.notifier).state = Metric.co2,
              child: Text(metric == Metric.co2 ? 'Air · CO₂ selected' : 'View air · CO₂', style: T.label.copyWith(color: C.onBrand)),
            ),
          ),
          if (moisture)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MoistureReading(label: 'PROBE 1 · UPPER', value: s.topMeasured ? s.topMoisture : null),
                ),
                const SizedBox(width: S.x4),
                Expanded(
                  child: _MoistureReading(label: 'PROBE 2 · LOWER', value: s.bottomMeasured ? s.bottomMoisture : null),
                ),
              ],
            )
          else ...[
            Text(metric == Metric.temperature ? 'COMPOST TEMPERATURE' : 'AIR · CO₂', style: T.caps.copyWith(color: C.onBrand)),
            const SizedBox(height: S.x2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: T.hero.copyWith(fontSize: 58, color: C.onBrand)),
            ),
            if (!measured) Text('Not measured · check the sensor connection', style: T.body.copyWith(color: C.onBrand)),
            if (metric == Metric.temperature) ...[
              Text(
                s.ambientMeasured ? 'Ambient air: ${s.ambientTemp.toStringAsFixed(1)} °C' : 'Ambient temperature not measured',
                style: T.body.copyWith(color: C.onBrand),
              ),
              if (measured && s.ambientMeasured)
                Text(
                  '${(s.topTemp - s.ambientTemp).abs().toStringAsFixed(1)} °C ${s.topTemp >= s.ambientTemp ? 'above' : 'below'} ambient',
                  style: T.small.copyWith(color: C.onBrand),
                ),
            ],
          ],
        ],
      ),
      children: [
        if (moisture) ...[
          const SectionLabel('MOISTURE HEAT MAP'),
          const SizedBox(height: S.x3),
          MoistureMap(snapshot: s),
          const SizedBox(height: S.x3),
          Text('Two measured points, not a scan of the whole bin. Colour does not imply measurements between probes.', style: T.small),
          if (!s.moistureCalibrated || !s.bottomMoistureCalibrated)
            Text(
              '${[if (!s.moistureCalibrated) 'Probe 1', if (!s.bottomMoistureCalibrated) 'Probe 2'].join(' and ')} uncalibrated · values are approximate.',
              style: T.small.copyWith(color: C.clay),
            ),
          TextButton(
            onPressed: () => Routes.calibration(context),
            child: Text('Calibrate probes', style: T.button),
          ),
          const SectionBreak(),
          PaperSegments<Zone>(
            values: const [Zone.top, Zone.bottom],
            selected: _moistureProbe,
            label: (z) => z == Zone.top ? 'Probe 1 history' : 'Probe 2 history',
            onChanged: (z) => setState(() => _moistureProbe = z),
          ),
          const SizedBox(height: S.x4),
        ] else ...[
          Text(
            metric == Metric.temperature
                ? 'One working compost temperature probe. The lower temperature sensor is unavailable and is not shown.'
                : 'CO₂ is context for activity, not a direct measurement of oxygen or compost readiness.',
            style: T.body,
          ),
          const SectionBreak(),
        ],
        const SectionLabel('LAST 24 HOURS', info: InfoTip.chart),
        const SizedBox(height: S.x2),
        Text(
          moisture
              ? '${zone == Zone.top ? 'Probe 1 · upper' : 'Probe 2 · lower'} moisture · shaded guide: 40–60'
              : metric == Metric.temperature
              ? 'Compost probe · °C'
              : 'Air sensor · ppm',
          style: T.small,
        ),
        const SizedBox(height: S.x3),
        SizedBox(
          height: 190,
          child: trendState.when(
            loading: () => const Center(child: CircularProgressIndicator(color: C.forest)),
            error: (_, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load this trend.', style: T.body),
                  TextButton(
                    onPressed: () => ref.invalidate(trendProvider(trendKey)),
                    child: Text('Retry trend', style: T.button),
                  ),
                ],
              ),
            ),
            data: (points) => points.isEmpty
                ? Center(
                    child: Text(
                      moisture && zone == Zone.bottom
                          ? 'No Probe 2 history yet. Available live readings still appear above.'
                          : 'No measurements for this chart yet.',
                      style: T.body,
                      textAlign: TextAlign.center,
                    ),
                  )
                : _Chart(points: points, metric: metric, logs: logs),
          ),
        ),
        const SizedBox(height: S.x4),
        Text('Dashed pink lines mark additions. They show timing, not proof of cause.', style: T.small),
        if (!measured) Text('Current reading unavailable. Any chart above contains past measurements only.', style: T.small),
        if (trend.isNotEmpty && !trendState.hasError) ...[const SizedBox(height: S.x4), _Stats(points: trend, metric: metric)],
        const SectionBreak(),
        const SectionLabel('WHAT IT MEANS'),
        const SizedBox(height: S.x3),
        Text(
          moisture
              ? 'Compare the two probes instead of averaging them: a dry spot and a wet spot can cancel each other out. '
                    'Percentages are relative to each probe’s dry/wet calibration, not water by weight. The 40–60 band is an app guide; check the compost by hand.'
              : metric == Metric.temperature
              ? 'Compare compost warmth with ambient air and its own history. Temperature alone cannot tell you what to add or whether compost is ready.'
              : 'CO₂ can change with microbial activity and ventilation. Read it alongside moisture, temperature and recent additions.',
          style: T.body,
        ),
        const SectionBreak(),
        const SectionLabel('RECENT ADDS'),
        const SizedBox(height: S.x2),
        if (logs.isEmpty) Text('No additions recorded yet.', style: T.small),
        for (final (i, l) in logs.take(4).indexed) ...[if (i > 0) const Hairline(), _LogRow(l)],
      ],
    );
  }
}

class _MoistureReading extends StatelessWidget {
  const _MoistureReading({required this.label, required this.value});
  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: T.caps.copyWith(color: C.onBrand, fontSize: 10.5)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value == null ? '—' : '${value!.round()}%', style: T.hero.copyWith(fontSize: 48, color: C.onBrand)),
      ),
      Text(value == null ? 'Not measured' : 'Relative moisture', style: T.small.copyWith(color: C.onBrand)),
    ],
  );
}

class _Chart extends StatelessWidget {
  const _Chart({required this.points, required this.metric, required this.logs});
  final List<TrendPoint> points;
  final Metric metric;
  final List<LogEntry> logs;

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = switch (metric) {
      Metric.moisture => (moistureLo, moistureHi),
      Metric.temperature => (0.0, 60.0),
      Metric.co2 => (900.0, 6000.0),
    };
    final values = points.map((p) => p.value).toList();
    var minY = math.min(values.reduce(math.min), lo);
    var maxY = math.max(values.reduce(math.max), hi);
    if (metric == Metric.co2) {
      minY = values.reduce(math.min) * 0.6;
      maxY = values.reduce(math.max) * 1.4;
    }
    final pad = math.max(1.0, (maxY - minY) * 0.12);
    final first = DateTime.now().subtract(const Duration(hours: 24));
    final spots = [for (final p in points) FlSpot(p.time.difference(first).inMinutes / 60, p.value)];
    String fmt(double v) => switch (metric) {
      Metric.moisture => '${v.round()}%',
      Metric.temperature => '${v.round()}°',
      Metric.co2 => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v.round()}',
    };
    // Adds within the window become markers on the line.
    final marks = [
      for (final l in logs.where((l) => l.added))
        if (l.time.isAfter(first)) l,
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
        minY: minY - pad,
        maxY: maxY + pad,
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: [if (metric == Metric.moisture) HorizontalRangeAnnotation(y1: lo, y2: hi, color: C.brand.withValues(alpha: 0.14))],
        ),
        extraLinesData: ExtraLinesData(
          verticalLines: [
            for (final l in marks) VerticalLine(x: l.time.difference(first).inMinutes / 60, color: C.pink, strokeWidth: 1.5, dashArray: [3, 4]),
          ],
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: C.line, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (v, meta) => (v == meta.min || v == meta.max) ? const SizedBox() : Text(fmt(v), style: T.small.copyWith(fontSize: 10.5)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              reservedSize: 22,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(v == 24 ? 'now' : '-${(24 - v).round()}h', style: T.small.copyWith(fontSize: 10.5)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => C.ink,
            tooltipBorderRadius: BorderRadius.circular(R.chip),
            getTooltipItems: (spots) => [for (final s in spots) LineTooltipItem(fmt(s.y), T.small.copyWith(color: Colors.white, fontWeight: FontWeight.w800))],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            curveSmoothness: 0.25,
            color: C.forest,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (s, bar) => s == bar.spots.last,
              getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 5, color: C.pink, strokeWidth: 2.5, strokeColor: C.surface),
            ),
            belowBarData: BarAreaData(show: true, color: C.forest.withValues(alpha: 0.05)),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 500),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.points, required this.metric});
  final List<TrendPoint> points;
  final Metric metric;

  @override
  Widget build(BuildContext context) {
    final v = points.map((p) => p.value).toList();
    final avg = v.reduce((a, b) => a + b) / v.length;
    String fmt(double x) => switch (metric) {
      Metric.moisture => '${x.round()}%',
      Metric.temperature => '${x.toStringAsFixed(1)}°',
      Metric.co2 => x >= 1000 ? '${(x / 1000).toStringAsFixed(1)}k' : '${x.round()}',
    };
    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(label, style: T.caps.copyWith(fontSize: 10)),
          const SizedBox(height: 4),
          Text(value, style: T.value.copyWith(fontSize: 17)),
        ],
      ),
    );
    return IntrinsicHeight(
      child: Row(
        children: [
          stat('LATEST', fmt(v.last)),
          const Hairline(vertical: true),
          stat('AVG', fmt(avg)),
          const Hairline(vertical: true),
          stat('LOW', fmt(v.reduce(math.min))),
          const Hairline(vertical: true),
          stat('HIGH', fmt(v.reduce(math.max))),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.l);
  final LogEntry l;

  @override
  Widget build(BuildContext context) {
    final ago = DateTime.now().difference(l.time);
    final when = ago.inMinutes < 60 ? '${ago.inMinutes}m ago' : (ago.inHours < 24 ? '${ago.inHours}h ago' : 'Yesterday');
    final color = switch (l.verdict) {
      Verdict.great => C.leaf,
      Verdict.careful => C.amber,
      Verdict.avoid => C.clay,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          Icon(l.item.icon, size: 20, color: color),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.item.name, style: T.heading.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600)),
                Text(l.added ? 'Added · $when' : 'Kept out · $when', style: T.small),
              ],
            ),
          ),
          if (l.xp > 0) PinkPill('+${l.xp} XP'),
        ],
      ),
    );
  }
}
