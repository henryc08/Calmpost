import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/health_score.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';

/// One zone of the bin: live values, a 24 h trend, and what it means.
class LayerScreen extends ConsumerStatefulWidget {
  const LayerScreen(this.zone, {super.key});
  final Zone zone;

  @override
  ConsumerState<LayerScreen> createState() => _LayerScreenState();
}

class _LayerScreenState extends ConsumerState<LayerScreen> {
  late Metric _metric = widget.zone == Zone.air ? Metric.co2 : Metric.moisture;

  List<Metric> get _metrics => widget.zone == Zone.air ? const [Metric.co2] : const [Metric.moisture, Metric.temperature];

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(healthProvider);
    final repo = ref.watch(repositoryProvider);
    final (title, sub, tone) = switch (widget.zone) {
      Zone.air => ('Air gap', 'The space under the lid. CO₂ shows how busy the microbes are.', Tone.moss),
      Zone.top => ('Top layer', 'Fresh scraps mixed with browns. This is where the action is.', Tone.leaf),
      Zone.bottom => ('Bottom layer', 'Older compost, slowly turning into fertilizer.', Tone.soil),
    };

    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: h == null
            ? const SizedBox()
            : ListView(
                padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.gutter, S.x8),
                children: [
                  Row(
                    children: [
                      Pressable(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(S.x3),
                          child: Icon(PhosphorIconsBold.caretLeft, color: C.muted, size: 26),
                        ),
                      ),
                      Expanded(child: Text(title, style: T.h1)),
                      Tag(_stageLabel(h.snapshot), tone: tone, dense: true),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(S.x3, 0, 0, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sub, style: T.body),
                        const SizedBox(height: S.x4),
                        _ValueTiles(zone: widget.zone, s: h.snapshot),
                        const SizedBox(height: S.x4),
                        if (_metrics.length > 1) ...[
                          _Segmented(
                            values: _metrics,
                            selected: _metric,
                            label: (m) => m == Metric.moisture ? 'Moisture' : 'Temperature',
                            onChanged: (m) => setState(() => _metric = m),
                          ),
                          const SizedBox(height: S.x3),
                        ],
                        Slab(
                          padding: const EdgeInsets.fromLTRB(S.x2, S.x4, S.x4, S.x3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: S.x3, bottom: S.x3),
                                child: Row(
                                  children: [
                                    Text('LAST 24 HOURS', style: T.eyebrow),
                                    const Spacer(),
                                    Container(
                                      width: 14,
                                      height: 10,
                                      decoration: BoxDecoration(color: C.leaf.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(3)),
                                    ),
                                    const SizedBox(width: 4),
                                    Text('Healthy range', style: T.small.copyWith(fontSize: 11.5)),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 200,
                                child: FutureBuilder<List<TrendPoint>>(
                                  key: ValueKey('${widget.zone}-$_metric-${ref.watch(scenarioProvider)}'),
                                  future: repo.trends(widget.zone, _metric),
                                  builder: (context, snap) => snap.hasData
                                      ? _TrendChart(points: snap.data!, metric: _metric, zone: widget.zone, ambient: h.snapshot.ambientTemp)
                                      : const SizedBox(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: S.x4),
                        _WrenExplains(zone: widget.zone, s: h.snapshot, mood: h.mood),
                      ].animate(interval: M.stagger).fadeIn(duration: M.base).slideY(begin: 0.06),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _stageLabel(BinSnapshot s) {
    final stage = widget.zone == Zone.bottom ? s.bottomStage : s.topStage;
    if (widget.zone == Zone.air) return s.co2 > 2000 ? 'Busy' : 'Calm';
    return switch (stage) {
      Stage.started || Stage.active => 'Active',
      Stage.hot => 'Hot phase',
      Stage.cooling => 'Cooling',
      Stage.curing => 'Curing',
      Stage.ready => 'Ready!',
      Stage.harvested => 'Harvested',
    };
  }
}

class _ValueTiles extends StatelessWidget {
  const _ValueTiles({required this.zone, required this.s});
  final Zone zone;
  final BinSnapshot s;

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String label, String value, String unit, Tone tone, String hint) => Expanded(
      child: Slab(
        color: tone.tint,
        edge: tone.face.withValues(alpha: 0.4),
        padding: const EdgeInsets.all(S.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: tone.face, size: 18),
                const SizedBox(width: 4),
                Text(label.toUpperCase(), style: T.eyebrow.copyWith(color: tone.lip, fontSize: 11)),
              ],
            ),
            const SizedBox(height: S.x2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: T.numL.copyWith(fontSize: 32, color: tone.lip)),
                Text(unit, style: T.title.copyWith(color: tone.lip)),
              ],
            ),
            const SizedBox(height: 2),
            Text(hint, style: T.small.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );

    if (zone == Zone.air) {
      return Row(
        children: [
          tile(PhosphorIconsFill.cloud, 'CO₂', '${s.co2.round()}', ' ppm', Tone.moss, 'Microbe breathing'),
          const SizedBox(width: S.x3),
          tile(
            s.co2SlopePerDay <= 0 ? PhosphorIconsFill.trendDown : PhosphorIconsFill.trendUp,
            'Trend',
            '${s.co2SlopePerDay > 0 ? '+' : ''}${s.co2SlopePerDay.toStringAsFixed(0)}',
            '%/day',
            Tone.sky,
            s.co2SlopePerDay < -5 ? 'Settling down' : 'Steady',
          ),
        ],
      );
    }
    final m = s.moisture(zone);
    final t = s.temp(zone);
    final mHint = m > moistureHi + 4 ? 'Too wet' : (m < moistureLo - 4 ? 'Too dry' : 'Just right');
    final delta = t - s.ambientTemp;
    return Row(
      children: [
        tile(PhosphorIconsFill.drop, 'Moisture', '${m.round()}', '%', m > moistureHi + 4 ? Tone.sky : (m < moistureLo - 4 ? Tone.flame : Tone.leaf), mHint),
        const SizedBox(width: S.x3),
        tile(
          PhosphorIconsFill.thermometerSimple,
          'Temp',
          t.toStringAsFixed(1),
          '°C',
          Tone.flame,
          '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}° vs room',
        ),
      ],
    );
  }
}

class _Segmented<V> extends StatelessWidget {
  const _Segmented({required this.values, required this.selected, required this.label, required this.onChanged});
  final List<V> values;
  final V selected;
  final String Function(V) label;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.bgDeep, borderRadius: BorderRadius.circular(R.button)),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: M.base,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: v == selected ? C.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(R.chip),
                    border: Border.all(color: v == selected ? C.border : Colors.transparent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(label(v).toUpperCase(), style: T.eyebrow.copyWith(color: v == selected ? C.ink : C.muted, fontSize: 12.5)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points, required this.metric, required this.zone, required this.ambient});
  final List<TrendPoint> points;
  final Metric metric;
  final Zone zone;
  final double ambient;

  @override
  Widget build(BuildContext context) {
    final color = switch (metric) {
      Metric.moisture => C.sky,
      Metric.temperature => C.flame,
      Metric.co2 => C.moss,
    };
    final (lo, hi) = switch (metric) {
      Metric.moisture => (moistureLo, moistureHi),
      Metric.temperature => zone == Zone.bottom ? (ambient - 2, ambient + 8) : (ambient + 5, ambient + 25),
      Metric.co2 => (900.0, 6000.0),
    };
    final values = points.map((p) => p.value).toList();
    var minY = [...values, lo].reduce((a, b) => a < b ? a : b);
    var maxY = [...values, hi].reduce((a, b) => a > b ? a : b);
    if (metric == Metric.co2) {
      minY = values.reduce((a, b) => a < b ? a : b) * 0.6;
      maxY = values.reduce((a, b) => a > b ? a : b) * 1.4;
    }
    final pad = (maxY - minY) * 0.12;
    final first = points.first.time;
    final spots = [for (final p in points) FlSpot(p.time.difference(first).inMinutes / 60, p.value)];
    String unit(double v) => switch (metric) {
      Metric.moisture => '${v.round()}%',
      Metric.temperature => '${v.round()}°',
      Metric.co2 => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v.round()}',
    };

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
        minY: minY - pad,
        maxY: maxY + pad,
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: [HorizontalRangeAnnotation(y1: lo, y2: hi, color: C.leaf.withValues(alpha: 0.12))],
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: C.border, strokeWidth: 1.5, dashArray: [4, 6]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => (v == meta.min || v == meta.max) ? const SizedBox() : Text(unit(v), style: T.small.copyWith(fontSize: 11)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              reservedSize: 24,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(v == 24 ? 'now' : '-${(24 - v).round()}h', style: T.small.copyWith(fontSize: 11)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => C.ink,
            tooltipBorderRadius: BorderRadius.circular(R.chip),
            getTooltipItems: (spots) => [for (final s in spots) LineTooltipItem(unit(s.y), T.small.copyWith(color: Colors.white, fontWeight: FontWeight.w900))],
          ),
          getTouchedSpotIndicator: (bar, idx) => [
            for (final _ in idx)
              TouchedSpotIndicatorData(
                FlLine(color: color.withValues(alpha: 0.4), strokeWidth: 2),
                FlDotData(
                  getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 6, color: color, strokeWidth: 3, strokeColor: Colors.white),
                ),
              ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: color,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (s, bar) => s == bar.spots.last,
              getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 6, color: color, strokeWidth: 3, strokeColor: Colors.white),
            ),
            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 600),
    );
  }
}

class _WrenExplains extends StatelessWidget {
  const _WrenExplains({required this.zone, required this.s, required this.mood});
  final Zone zone;
  final BinSnapshot s;
  final WrenMood mood;

  @override
  Widget build(BuildContext context) {
    final text = switch (zone) {
      Zone.air =>
        s.co2SlopePerDay < -5
            ? 'CO₂ is dropping. The microbes are winding down, which is what finishing compost looks like.'
            : 'Lots of CO₂ means lots of microbes eating. The vent holes keep it from going sour.',
      Zone.top =>
        s.topMoisture > moistureHi + 4
            ? 'It\'s soggy up here. Too much water pushes the air out and things start to smell. Browns will fix it.'
            : s.topMoisture < moistureLo - 4
            ? 'It\'s too dry for the microbes to work. Wet greens or a splash of water will wake them up.'
            : 'Damp like a wrung-out sponge. That\'s perfect. The warmth means it\'s breaking down nicely.',
      Zone.bottom =>
        s.bottomStage == Stage.ready
            ? 'This layer is done: cool, dark and crumbly. Harvest it for your plants!'
            : 'Cooling and curing. In a few weeks this will be rich, finished compost.',
    };
    return Slab(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wren(mood: mood, size: 64),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WREN SAYS', style: T.eyebrow),
                const SizedBox(height: S.x1),
                Text(
                  text,
                  style: T.bodyStrong.copyWith(color: C.inkSoft, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
