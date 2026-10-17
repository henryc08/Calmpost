import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models.dart';
import '../../state/celebrations.dart';
import '../../state/game.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';
import 'verdict_panel.dart';

/// Log a scrap: search or snap a photo, then Wren gives a verdict based on
/// the bin's live readings.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key, this.initial});
  final FoodItem? initial;

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

enum _Phase { browsing, scanning, thinking, verdict }

class _LogScreenState extends ConsumerState<LogScreen> {
  final _search = TextEditingController();
  String _query = '';
  _Phase _phase = _Phase.browsing;
  FoodItem? _selected;
  Advice? _advice;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check(widget.initial!));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _check(FoodItem item) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _selected = item;
      _phase = _Phase.thinking;
      _advice = null;
    });
    final advice = await ref.read(repositoryProvider).checkItem(item);
    if (!mounted || _selected != item) return;
    switch (advice.verdict) {
      case Verdict.great:
        Sfx.success();
      case Verdict.careful:
        Sfx.play(Sound.careful);
      case Verdict.avoid:
        Sfx.play(Sound.avoid);
    }
    setState(() {
      _advice = advice;
      _phase = _Phase.verdict;
    });
  }

  Future<void> _scan() async {
    setState(() => _phase = _Phase.scanning);
    final item = await ref.read(repositoryProvider).identifyPhoto();
    if (!mounted || _phase != _Phase.scanning) return;
    _check(item);
  }

  void _commit({required bool added}) {
    final advice = _advice;
    if (advice == null) return;
    final suggested = ref.read(suggestionProvider)?.add.map((f) => f.id) ?? const <String>[];
    final out = ref.read(gameProvider.notifier).recordLog(advice, added: added, suggestedIds: suggested);
    if (added) ref.read(repositoryProvider).logItem(advice.item);
    final toast = ref.read(toastProvider.notifier);
    if (out.followed) {
      toast.show('You followed Wren\'s tip!', xp: out.xp);
    } else if (!added && advice.verdict == Verdict.avoid) {
      toast.show('Good call keeping it out', xp: out.xp);
    } else if (added) {
      toast.show('${advice.item.name} logged');
    }
    Navigator.of(context).pop();
  }

  void _reset() => setState(() {
    _phase = _Phase.browsing;
    _selected = null;
    _advice = null;
  });

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final mood = ref.watch(healthProvider)?.mood ?? WrenMood.happy;
    final suggested = ref.watch(suggestionProvider)?.add.map((f) => f.id).toSet() ?? {};
    final results = repo.searchFoods(_query);
    final groups = [
      ('Greens', 'Wet, nitrogen-rich scraps', Tone.leaf, FoodCategory.green),
      ('Browns', 'Dry, carbon-rich material', Tone.soil, FoodCategory.brown),
      ('Keep out', 'Never goes in the bin', Tone.coral, FoodCategory.avoid),
    ];

    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.gutter, 0),
                  child: Row(
                    children: [
                      Pressable(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(S.x3),
                          child: Icon(PhosphorIconsBold.x, color: C.faint, size: 26),
                        ),
                      ),
                      const SizedBox(width: S.x1),
                      Expanded(child: Text('What are you adding?', style: T.h2)),
                      Wren(mood: mood, size: 54),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, S.x2),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SearchField(controller: _search, onChanged: (q) => setState(() => _query = q)),
                      ),
                      const SizedBox(width: S.x3),
                      ChunkyCircle(
                        size: 54,
                        face: C.sky,
                        lip: C.skyLip,
                        lipHeight: 4,
                        onPressed: _scan,
                        child: const Icon(PhosphorIconsFill.camera, color: Colors.white, size: 26),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, 260),
                    children: [
                      for (final (title, sub, tone, cat) in groups) ...[
                        if (results.any((f) => f.category == cat)) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: S.x4, bottom: S.x3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(title, style: T.h2.copyWith(color: tone.lip)),
                                const SizedBox(width: S.x2),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(sub, style: T.small),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: S.x3,
                            crossAxisSpacing: S.x3,
                            childAspectRatio: 0.92,
                            children: [
                              for (final f in results.where((f) => f.category == cat))
                                _FoodTile(f, tone: tone, selected: _selected?.id == f.id, suggested: suggested.contains(f.id), onTap: () => _check(f)),
                            ].animate(interval: 25.ms).fadeIn(duration: 220.ms).scale(begin: const Offset(0.92, 0.92)),
                          ),
                        ],
                      ],
                      if (results.isEmpty) _NoResults(query: _query),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_phase == _Phase.scanning) Positioned.fill(child: _ScanOverlay(onCancel: _reset)),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) => SlideTransition(
                position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a),
                child: child,
              ),
              child: switch (_phase) {
                _Phase.thinking => ThinkingPanel(key: const ValueKey('thinking'), item: _selected!),
                _Phase.verdict => VerdictPanel(
                  key: ValueKey('verdict-${_advice!.item.id}'),
                  advice: _advice!,
                  followsTip: suggested.contains(_advice!.item.id),
                  onAdd: () => _commit(added: true),
                  onKeepOut: () => _commit(added: false),
                  onPair: _check,
                  onBack: _reset,
                ),
                _ => const SizedBox.shrink(key: ValueKey('none')),
              },
            ),
          ),
          if (_phase == _Phase.verdict && _advice?.verdict == Verdict.great)
            const Positioned.fill(child: LeafBurst(origin: Alignment(0, 0.45), count: 34, power: 0.8)),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(R.button),
        border: Border.all(color: C.border, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: S.x3),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.magnifyingGlass, color: C.faint, size: 22),
          const SizedBox(width: S.x2),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: T.bodyStrong,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Banana peel, cardboard…',
                hintStyle: T.body.copyWith(color: C.faint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile(this.f, {required this.tone, required this.selected, required this.suggested, required this.onTap});
  final FoodItem f;
  final Tone tone;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: Pressable(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: M.fast,
              decoration: BoxDecoration(color: selected ? tone.face : C.border, borderRadius: BorderRadius.circular(R.button + 2)),
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
              child: Container(
                decoration: BoxDecoration(color: selected ? tone.tint : C.surface, borderRadius: BorderRadius.circular(R.button)),
                padding: const EdgeInsets.all(S.x2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconBlob(f.icon, tone: tone, size: 46),
                    const SizedBox(height: S.x2),
                    Text(
                      f.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: T.small.copyWith(color: C.ink, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.15),
                    ),
                  ],
                ),
              ),
            ),
            if (suggested)
              Positioned(
                top: -6,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: C.sun,
                    borderRadius: BorderRadius.circular(R.chip),
                    border: Border.all(color: C.bg, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsFill.lightning, size: 11, color: C.soilDeep),
                      Text('TIP', style: T.eyebrow.copyWith(fontSize: 10, color: C.soilDeep)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: S.x8),
      child: Column(
        children: [
          const Wren(mood: WrenMood.okay, size: 110, ground: true),
          const SizedBox(height: S.x3),
          Text('Wren doesn\'t know "$query" yet', style: T.title, textAlign: TextAlign.center),
          const SizedBox(height: S.x1),
          Text('Try snapping a photo instead.', style: T.body),
        ],
      ),
    );
  }
}

/// Mock photo ID: a viewfinder with a scan line while "Gemini" looks.
class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: C.ink.withValues(alpha: 0.92),
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Pressable(
                onTap: onCancel,
                child: const Padding(
                  padding: EdgeInsets.all(S.x4),
                  child: Icon(PhosphorIconsBold.x, color: Colors.white70, size: 26),
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 250,
              height: 250,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _ViewfinderPainter())),
                  const Center(child: Icon(PhosphorIconsFill.orangeSlice, size: 110, color: C.sun)),
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 18,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(color: C.leaf, borderRadius: BorderRadius.circular(4)),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: 0, end: 206, duration: 900.ms, curve: Curves.easeInOut),
                ],
              ),
            ),
            const SizedBox(height: S.x6),
            Text('Wren is taking a look…', style: T.h2.copyWith(color: Colors.white)),
            const SizedBox(height: S.x2),
            Text('Photo ID with Gemini', style: T.small.copyWith(color: Colors.white60)),
            const Spacer(flex: 2),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const l = 36.0;
    final w = size.width;
    final h = size.height;
    for (final (o, dx, dy) in [(Offset.zero, 1.0, 1.0), (Offset(w, 0), -1.0, 1.0), (Offset(0, h), 1.0, -1.0), (Offset(w, h), -1.0, -1.0)]) {
      canvas.drawLine(o, o + Offset(l * dx, 0), p);
      canvas.drawLine(o, o + Offset(0, l * dy), p);
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => false;
}
