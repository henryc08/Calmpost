import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/health_score.dart' show ZoneState;
import '../../domain/models.dart';
import '../../ui/ui.dart';

/// First-run: meet Wren, learn the one rule, see the garden, pair the bin.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  int _pairing = 0; // 0 idle, 1 searching, 2 found

  static const _count = 4;

  void _next() {
    if (_page == _count - 1) {
      if (_pairing == 0) {
        setState(() => _pairing = 1);
        Future.delayed(const Duration(milliseconds: 1800), () {
          if (!mounted) return;
          Sfx.success();
          setState(() => _pairing = 2);
        });
        return;
      }
      if (_pairing == 2) widget.onDone();
      return;
    }
    _pages.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _page < _count - 1
        ? 'Continue'
        : switch (_pairing) {
            0 => 'Pair my bin',
            1 => 'Searching…',
            _ => 'Let\'s compost',
          };
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x2, S.x3, S.gutter, 0),
              child: Row(
                children: [
                  Pressable(
                    onTap: _page == 0 ? null : () => _pages.previousPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic),
                    child: Padding(
                      padding: const EdgeInsets.all(S.x3),
                      child: Icon(PhosphorIconsBold.arrowLeft, color: _page == 0 ? Colors.transparent : C.faint, size: 24),
                    ),
                  ),
                  Expanded(child: ProgressBar(value: (_page + 1) / _count, height: 16)),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  const _Page(
                    art: Wren(mood: WrenMood.thriving, size: 220, ground: true, hat: WrenHat.sprout),
                    title: 'Meet Wren',
                    body: 'Wren lives in your compost bin. Sensors tell Wren how wet, warm and busy it is, and Wren tells you what to add.',
                  ),
                  _Page(
                    art: const _RuleArt(),
                    title: 'Care earns XP.\nVolume never does.',
                    body: 'Follow Wren\'s tips, keep both layers balanced and build a streak. Dumping in more food won\'t earn a single point.',
                  ),
                  const _Page(
                    art: _GardenArt(),
                    title: 'Grow a garden',
                    body: 'Every healthy bin day grows a plant. Harvest compost to unlock rare ones, and climb weekly leagues with friends.',
                  ),
                  _Page(
                    art: SizedBox(
                      width: 280,
                      child: BinScene(
                        states: const {Zone.air: ZoneState.good, Zone.top: ZoneState.good, Zone.bottom: ZoneState.good},
                        mood: _pairing == 2 ? WrenMood.thriving : WrenMood.okay,
                        hat: WrenHat.sprout,
                      ),
                    ),
                    title: _pairing == 2 ? 'Found "Kitchen bin"' : 'Pair your bin',
                    body: _pairing == 2
                        ? 'Your ESP32 is online and streaming moisture, temperature and CO₂.'
                        : 'Turn on your Calmpost bin and keep your phone nearby.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
              child: ChunkyButton(label: label, onPressed: _pairing == 1 ? null : _next),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.art, required this.title, required this.body});
  final Widget art;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          art.animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.85, 0.85), curve: Curves.easeOutBack, duration: 600.ms),
          const SizedBox(height: S.x6),
          Text(title, textAlign: TextAlign.center, style: T.h1).animate().fadeIn(delay: 150.ms).slideY(begin: 0.2),
          const SizedBox(height: S.x3),
          Text(body, textAlign: TextAlign.center, style: T.body.copyWith(fontSize: 16)).animate().fadeIn(delay: 250.ms),
        ],
      ),
    );
  }
}

class _RuleArt extends StatelessWidget {
  const _RuleArt();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text, bool good, int i) => Padding(
      padding: const EdgeInsets.only(bottom: S.x2),
      child: Slab(
        color: good ? C.leafTint : C.coralTint,
        edge: (good ? C.leaf : C.coral).withValues(alpha: 0.4),
        radius: R.button + 2,
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
        child: Row(
          children: [
            Icon(icon, color: good ? C.leaf : C.coral, size: 22),
            const SizedBox(width: S.x3),
            Expanded(child: Text(text, style: T.bodyStrong.copyWith(fontSize: 14))),
            Text(good ? '+15 XP' : '0 XP', style: T.numM.copyWith(fontSize: 14, color: good ? C.leafLip : C.coralLip)),
          ],
        ),
      ),
    ).animate().fadeIn(delay: (200 + i * 120).ms).slideX(begin: 0.15);
    return SizedBox(
      width: 300,
      child: Column(
        children: [
          row(PhosphorIconsFill.lightbulb, 'Followed Wren\'s tip', true, 0),
          row(PhosphorIconsFill.drop, 'Kept layers in range', true, 1),
          row(PhosphorIconsFill.trash, 'Dumped in extra food', false, 2),
        ],
      ),
    );
  }
}

class _GardenArt extends StatelessWidget {
  const _GardenArt();

  @override
  Widget build(BuildContext context) {
    const species = [PlantSpecies.tulip, PlantSpecies.sunflower, PlantSpecies.fern, PlantSpecies.mushroom, PlantSpecies.pumpkin];
    return Container(
      width: 300,
      height: 170,
      decoration: BoxDecoration(color: C.grass, borderRadius: BorderRadius.circular(R.card)),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [for (final (i, s) in species.indexed) Plant(s, size: 58 + (i == 2 ? 10 : 0), grow: true).animate().fadeIn(delay: (i * 140).ms)],
      ),
    );
  }
}
