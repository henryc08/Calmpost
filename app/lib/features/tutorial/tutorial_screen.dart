import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../state/game.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

const _seenKey = 'tutorial_seen_v1';

/// Whether the first-launch composting guide has been finished or skipped.
/// Without storage (tests, previews) it counts as seen so it never gets in the way.
final tutorialSeenProvider = StateProvider<bool>((ref) {
  final storage = ref.watch(gameStorageProvider);
  return storage == null || (storage.getBool(_seenKey) ?? false);
});

void markTutorialSeen(WidgetRef ref) {
  ref.read(gameStorageProvider)?.setBool(_seenKey, true);
  ref.read(tutorialSeenProvider.notifier).state = true;
}

/// Shows the guide on first launch, then the app.
class TutorialGate extends ConsumerWidget {
  const TutorialGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(tutorialSeenProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: seen ? child : const TutorialScreen(),
    );
  }
}

class _Page {
  const _Page(this.title, this.body, this.art);
  final String title;
  final String body;
  final Widget art;
}

final _pages = [
  const _Page('What is composting?', 'Food scraps and leaves break down into rich, dark soil.', _BinArt()),
  const _Page('Greens and browns', 'Mix one part wet greens with two parts dry browns.', _GreensBrownsArt()),
  const _Page('Microbes do the work', 'Give them water and air, and they heat the pile as they eat.', _MicrobesArt()),
  const _Page('Why it matters', 'Less waste in landfills, and better soil for gardens.', _GrowthArt()),
  const _Page('Calmpost has your back', 'Sensors watch your bin and tell you what it needs next.', _SensorArt()),
];

class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _last => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      markTutorialSeen(ref);
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, 0),
              child: Row(
                children: [
                  Icon(PhosphorIconsFill.plant, color: C.brand, size: 20),
                  const SizedBox(width: S.x1),
                  Text('Calmpost', style: T.heading.copyWith(fontFamily: 'Fraunces', fontWeight: FontWeight.w500, color: C.forest)),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _last ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: _last,
                      child: OutlinedButton(
                        onPressed: () => markTutorialSeen(ref),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: C.surface,
                          foregroundColor: C.forest,
                          side: const BorderSide(color: C.forest, width: 1.5),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: S.x4),
                          minimumSize: const Size(0, 36),
                        ),
                        child: Text('Skip', style: T.button.copyWith(fontSize: 13, color: C.forest)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _PageBody(page: _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x5, S.x3, S.x5, S.x5),
              child: Row(
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 5),
                      width: i == _index ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(color: i == _index ? C.brand : C.line, borderRadius: BorderRadius.circular(4)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: C.brand,
                      foregroundColor: C.onBrand,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: S.x5, vertical: S.x3),
                    ),
                    child: Text(_last ? 'Start composting' : 'Next', style: T.button.copyWith(color: C.onBrand, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page});
  final _Page page;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 220, child: Center(child: page.art)),
                const SizedBox(height: S.x3),
                Text(page.title, textAlign: TextAlign.center, style: T.title),
                const SizedBox(height: S.x3),
                Text(page.body, textAlign: TextAlign.center, style: T.body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Repeats [builder] with t going 0→1 every [period]. Holds still when the
/// system asks for reduced motion.
class _Loop extends StatefulWidget {
  const _Loop({required this.period, required this.builder});
  final Duration period;
  final Widget Function(double t) builder;

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c
        ..stop()
        ..value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, _) => widget.builder(_c.value));
}

double _bob(double t, [double phase = 0]) => -6 * (0.5 - 0.5 * math.cos(2 * math.pi * (t + phase)));

class _BinArt extends StatelessWidget {
  const _BinArt();

  @override
  Widget build(BuildContext context) {
    const items = [(PhosphorIconsFill.orangeSlice, C.amber, 28.0, 0.0), (PhosphorIconsFill.egg, C.clay, 62.0, 0.66), (PhosphorIconsFill.leaf, C.leaf, 96.0, 0.33)];
    return SizedBox(
      width: 160,
      height: 200,
      child: _Loop(
        period: const Duration(milliseconds: 2400),
        builder: (t) => Stack(
          children: [
            for (final (icon, color, left, phase) in items)
              Builder(builder: (_) {
                final p = (t + phase) % 1;
                final fall = Curves.easeIn.transform((p / 0.75).clamp(0, 1));
                final opacity = p < 0.3 ? p / 0.3 : (p > 0.6 ? ((0.75 - p) / 0.15).clamp(0.0, 1.0) : 1.0);
                return Positioned(
                  left: left,
                  top: -40 + fall * 120,
                  child: Opacity(opacity: opacity, child: Icon(icon, color: color, size: 30)),
                );
              }),
            Positioned(
              left: 15,
              bottom: 0,
              child: Container(
                width: 130,
                height: 92,
                decoration: const BoxDecoration(
                  color: C.forest,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(26)),
                ),
                child: const Icon(PhosphorIconsFill.recycle, color: C.sprout, size: 36),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GreensBrownsArt extends StatelessWidget {
  const _GreensBrownsArt();

  Widget _side(IconData icon, Color iconColor, Color bg, String name, String hint) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 38),
          ),
          const SizedBox(height: S.x2),
          Text(name, style: T.heading.copyWith(fontSize: 14, fontWeight: FontWeight.w800)),
          Text(hint, style: T.small),
        ],
      );

  @override
  Widget build(BuildContext context) => _Loop(
        period: const Duration(seconds: 2),
        builder: (t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(offset: Offset(0, _bob(t)), child: _side(PhosphorIconsFill.carrot, C.leaf, C.leafSoft, 'Greens', 'scraps, coffee')),
            const SizedBox(width: S.x5),
            Transform.translate(offset: Offset(0, _bob(t, 0.5)), child: _side(PhosphorIconsFill.package, C.loam, C.amberSoft, 'Browns', 'leaves, cardboard')),
          ],
        ),
      );
}

class _MicrobesArt extends StatelessWidget {
  const _MicrobesArt();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: S.x2),
              Text(text, style: T.heading.copyWith(fontSize: 13.5)),
            ],
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Loop(
          period: const Duration(milliseconds: 5000),
          builder: (t) {
            // Up then back down, like the preview's alternate animation.
            final level = 0.15 + 0.67 * Curves.easeInOut.transform(t < 0.5 ? t * 2 : 2 - t * 2);
            return Container(
              width: 28,
              height: 160,
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(heightFactor: level, widthFactor: 1, child: const ColoredBox(color: C.amber)),
            );
          },
        ),
        const SizedBox(width: S.x5),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(PhosphorIconsFill.drop, C.water, 'Damp, not soggy'),
            row(PhosphorIconsFill.wind, C.muted, 'Plenty of air'),
            row(PhosphorIconsFill.fire, C.amber, 'Gets warm'),
          ],
        ),
      ],
    );
  }
}

class _GrowthArt extends StatefulWidget {
  const _GrowthArt();

  @override
  State<_GrowthArt> createState() => _GrowthArtState();
}

class _GrowthArtState extends State<_GrowthArt> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const heights = [45.0, 75.0, 105.0, 135.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < heights.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                final start = i * 0.13;
                final grow = Curves.easeOutBack.transform(((_c.value - start) / 0.6).clamp(0.0, 1.0));
                return Container(
                  width: 34,
                  height: math.max(0, heights[i] * grow),
                  decoration: const BoxDecoration(color: C.brand, borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
                );
              },
            ),
          ),
        _Loop(
          period: const Duration(seconds: 2),
          builder: (t) => Transform.translate(offset: Offset(0, _bob(t)), child: const Icon(PhosphorIconsFill.plant, color: C.leaf, size: 46)),
        ),
      ],
    );
  }
}

class _SensorArt extends StatelessWidget {
  const _SensorArt();

  @override
  Widget build(BuildContext context) {
    Widget reading(IconData icon, Color color, String name, String value) => Padding(
          padding: const EdgeInsets.only(bottom: S.x3),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: S.x2),
              Text(name, style: T.heading.copyWith(fontSize: 13)),
              const Spacer(),
              Text(value, style: T.num.copyWith(color: color)),
            ],
          ),
        );
    return _Loop(
      period: const Duration(milliseconds: 2400),
      builder: (t) => Transform.translate(
        offset: Offset(0, _bob(t)),
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(S.x4),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              reading(PhosphorIconsFill.thermometer, C.amber, 'Temp', '52°C'),
              reading(PhosphorIconsFill.drop, C.water, 'Moisture', '58%'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(color: C.leafSoft, borderRadius: BorderRadius.circular(12)),
                child: Text('Looking healthy', textAlign: TextAlign.center, style: T.heading.copyWith(fontSize: 13, color: C.leaf)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
