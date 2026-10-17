import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/health_score.dart';
import '../../domain/models.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import '../../ui/info_dot.dart';

/// Live readings per zone, a 24 h chart with the healthy band, and what it means.
class LayersScreen extends ConsumerStatefulWidget {
  const LayersScreen({super.key});

  @override
  ConsumerState<LayersScreen> createState() => _LayersScreenState();
}

class _LayersScreenState extends ConsumerState<LayersScreen> {
  Zone _zone = Zone.top;
  Metric _metric = Metric.moisture;

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(healthProvider);
    if (h == null) return const SizedBox();
    final s = h.snapshot;
    final metric = _zone == Zone.air ? Metric.co2 : _metric;
    final trend = ref.watch(trendProvider((_zone, metric))).valueOrNull ?? const <TrendPoint>[];
    final logs = ref.watch(gameProvider.select((g) => g.logs));

    final unmeasured = switch ((_zone, metric)) {
      (Zone.air, _) => !s.airMeasured,
      (Zone.bottom, Metric.temperature) => !s.bottomTemperatureMeasured,
      (Zone.bottom, _) => !s.bottomMeasured,
      (Zone.top, Metric.temperature) => !s.topTemperatureMeasured,
      _ => !s.topMeasured,
    };
    final (value, unit) = switch (metric) {
      _ when unmeasured => ('—', ''),
      Metric.moisture => ('${s.moisture(_zone).round()}', '%'),
      Metric.temperature => (s.temp(_zone).toStringAsFixed(1), '°C'),
      Metric.co2 => ('${s.co2.round()}', ' ppm'),
    };
    final state = zoneState(s, _zone);
    final (stateLabel, stateColor) = switch (state) {
      ZoneState.wet => ('Too wet', C.water),
      ZoneState.dry => ('Too dry', C.amber),
      ZoneState.hot => ('High', C.clay),
      ZoneState.unknown => ('Not measured', C.muted),
      _ => ('In range', C.brandDeep),
    };
    final stage = _zone == Zone.bottom ? s.bottomStage : s.topStage;

    return BrandPage(
      title: 'Layers',
      subtitle: s.readingsStale ? 'Kitchen bin · last reading ${s.ageLabel(DateTime.now())}' : 'Kitchen bin · live',
      trailing: s.readingsStale ? null : const LiveDot(color: C.onBrand),
      hero: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BandSegments<Zone>(
            values: const [Zone.top, Zone.bottom, Zone.air],
            selected: _zone,
            label: (z) => switch (z) {
              Zone.top => 'Top layer',
              Zone.bottom => 'Bottom layer',
              Zone.air => 'Air gap',
            },
            onChanged: (z) => setState(() => _zone = z),
          ),
          const SizedBox(height: S.x5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: T.hero.copyWith(fontSize: 72, color: C.onBrand)),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4),
                child: Text(unit, style: T.heading.copyWith(color: C.onBrandMuted)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: C.onBrand, borderRadius: BorderRadius.circular(R.pill)),
                  child: Text(stateLabel.toUpperCase(), style: T.caps.copyWith(color: stateColor, fontSize: 10.5)),
                ),
              ),
            ],
          ),
          Text(_heroLine(_zone, s), style: T.body.copyWith(color: C.onBrand)),
        ],
      ),
      children: [
        if (_zone != Zone.air) ...[
          PaperSegments<Metric>(
            values: const [Metric.moisture, Metric.temperature],
            selected: _metric,
            label: (m) => m == Metric.moisture ? 'Moisture' : 'Temperature',
            onChanged: (m) => setState(() => _metric = m),
          ),
          const SizedBox(height: S.x5),
        ],
        SectionLabel(
          'LAST 24 HOURS',
          info: InfoTip.chart,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 8,
                decoration: BoxDecoration(color: C.brand.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 5),
              Text('Healthy range', style: T.small.copyWith(fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        SizedBox(
          height: 190,
          child: trend.isEmpty ? const SizedBox() : _Chart(points: trend, metric: metric, zone: _zone, ambient: s.ambientTemp, logs: logs),
        ),
        const SizedBox(height: S.x4),
        Row(
          children: [
            Container(width: 10, height: 2, color: C.pink),
            const SizedBox(width: 6),
            Expanded(child: Text('Dashed lines mark when something was added', style: T.small.copyWith(fontSize: 11))),
          ],
        ),
        const SizedBox(height: S.x4),
        if (trend.isNotEmpty) _Stats(points: trend, metric: metric),
        const SectionBreak(),
        const SectionLabel('WHAT IT MEANS'),
        const SizedBox(height: S.x3),
        Text(
          unmeasured ? 'No usable reading from this sensor. Unknown is not zero; check the sensor connection.' : _meaning(_zone, s),
          style: T.body.copyWith(fontSize: 15),
        ),
        if (!s.moistureCalibrated && _zone != Zone.air) Text('Moisture is uncalibrated: treat the percentage as an estimate.', style: T.small),
        if (_zone != Zone.air && !unmeasured) ...[
          const SectionBreak(),
          SectionLabel('LIFE CYCLE', trailing: Text('Guide from sensor trends', style: T.small.copyWith(fontSize: 11))),
          const SizedBox(height: S.x4),
          _StageLine(stage: stage),
        ],
        const SectionBreak(),
        const SectionLabel('RECENT ADDS'),
        const SizedBox(height: S.x2),
        for (final (i, l) in logs.take(4).indexed) ...[if (i > 0) const Hairline(), _LogRow(l)],
      ].animate(interval: M.stagger).fadeIn(duration: 380.ms, curve: M.ease),
    );
  }

  static String _heroLine(Zone z, BinSnapshot s) => switch (z) {
    Zone.top when !s.topTemperatureMeasured || !s.ambientMeasured => 'Fresh scraps and browns · temperature unavailable',
    Zone.air when !s.airMeasured => 'CO₂ unavailable · check the air sensor',
    Zone.top => 'Fresh scraps and browns · ${s.topTemp.round()}°C, ${(s.topTemp - s.ambientTemp).round()}° above the room',
    Zone.bottom when !s.bottomMeasured => 'Older compost, slowly finishing · no probe here yet',
    Zone.bottom => 'Older compost, slowly finishing · ${s.bottomTemp.round()}°C',
    Zone.air => 'CO₂ in the gap under the lid · ${s.co2SlopePerDay >= 0 ? 'rising' : 'falling'} ${s.co2SlopePerDay.abs().round()}% a day',
  };

  static String _meaning(Zone z, BinSnapshot s) => switch (z) {
    Zone.air =>
      s.co2SlopePerDay < -5
          ? 'CO₂ is dropping day over day. The microbes are winding down, which is what finishing compost looks like.'
          : 'CO₂ is the microbes breathing. Steady, high readings mean they are busy; the vent holes keep the bin from going sour.',
    Zone.top =>
      s.topMoisture > moistureHi + 4
          ? 'Too much water pushes the air out, and the bin starts to smell. Add dry browns like cardboard or leaves.'
          : s.topMoisture < moistureLo - 4
          ? 'Too dry for the microbes to work. Wet greens or a splash of water will get it going again.'
          : 'Damp like a wrung-out sponge, which is exactly right. The warmth means it is breaking down nicely.',
    Zone.bottom when !s.bottomMeasured =>
      'There is no probe in this layer yet, so its moisture and temperature are unknown. Its stage is a guide from the top layer and the CO₂.',
    Zone.bottom =>
      s.bottomStage == Stage.ready
          ? 'This layer is done: cool, dark and crumbly. Harvest it for your plants.'
          : s.bottomMoisture < moistureLo - 4
          ? 'The finishing layer is drying out. A little water keeps the last stage of curing moving.'
          : 'Cooling and curing. In a few weeks this will be rich, finished compost.',
  };
}

class _Chart extends StatelessWidget {
  const _Chart({required this.points, required this.metric, required this.zone, required this.ambient, required this.logs});
  final List<TrendPoint> points;
  final Metric metric;
  final Zone zone;
  final double ambient;
  final List<LogEntry> logs;

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = switch (metric) {
      Metric.moisture => (moistureLo, moistureHi),
      Metric.temperature => zone == Zone.bottom ? (ambient - 2, ambient + 8) : (ambient + 5, ambient + 25),
      Metric.co2 => (900.0, 6000.0),
    };
    final values = points.map((p) => p.value).toList();
    var minY = math.min(values.reduce(math.min), lo);
    var maxY = math.max(values.reduce(math.max), hi);
    if (metric == Metric.co2) {
      minY = values.reduce(math.min) * 0.6;
      maxY = values.reduce(math.max) * 1.4;
    }
    final pad = (maxY - minY) * 0.12;
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
          horizontalRangeAnnotations: [HorizontalRangeAnnotation(y1: lo, y2: hi, color: C.brand.withValues(alpha: 0.14))],
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
            isCurved: true,
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
          stat('NOW', fmt(v.last)),
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

/// Minimal horizontal life-cycle: dots on a line, current stage highlighted.
class _StageLine extends StatelessWidget {
  const _StageLine({required this.stage});
  final Stage stage;

  static const _steps = [(Stage.active, 'Active'), (Stage.hot, 'Hot'), (Stage.cooling, 'Cooling'), (Stage.curing, 'Curing'), (Stage.ready, 'Ready')];

  @override
  Widget build(BuildContext context) {
    final current = _steps.lastIndexWhere((e) => e.$1.index <= stage.index).clamp(0, _steps.length - 1);
    return Column(
      children: [
        SizedBox(
          height: 18,
          child: LayoutBuilder(
            builder: (context, c) {
              final step = c.maxWidth / (_steps.length - 1);
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(left: 0, right: 0, child: Container(height: 2, color: C.line)),
                  Positioned(
                    left: 0,
                    width: step * current,
                    child: Container(height: 2, color: C.forest),
                  ),
                  for (var i = 0; i < _steps.length; i++)
                    Positioned(
                      left: step * i - (i == current ? 9 : 5),
                      child: i == current
                          ? Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: C.pink,
                                shape: BoxShape.circle,
                                border: Border.all(color: C.paper, width: 3),
                              ),
                            )
                          : Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: i < current ? C.forest : C.line, shape: BoxShape.circle),
                            ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: S.x2),
        Row(
          children: [
            for (var i = 0; i < _steps.length; i++)
              Expanded(
                child: Text(
                  _steps[i].$2,
                  textAlign: i == 0 ? TextAlign.left : (i == _steps.length - 1 ? TextAlign.right : TextAlign.center),
                  style: T.small.copyWith(fontSize: 11.5, color: i == current ? C.ink : C.muted, fontWeight: i == current ? FontWeight.w800 : FontWeight.w600),
                ),
              ),
          ],
        ),
      ],
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
