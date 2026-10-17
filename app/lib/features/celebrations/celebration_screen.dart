import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/xp_rules.dart';
import '../../state/celebrations.dart';
import '../../state/game.dart';
import '../../ui/ui.dart';

/// Route used by the shell to show a celebration full-screen.
Route<void> celebrationRoute(Celebration c) => PageRouteBuilder<void>(
  opaque: true,
  transitionDuration: const Duration(milliseconds: 380),
  reverseTransitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (context, a, b) => CelebrationScreen(c),
  transitionsBuilder: (context, a, b, child) => FadeTransition(
    opacity: a,
    child: ScaleTransition(
      scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
);

class CelebrationScreen extends StatelessWidget {
  const CelebrationScreen(this.c, {super.key});
  final Celebration c;

  @override
  Widget build(BuildContext context) {
    final body = switch (c) {
      StreakCelebration s => _StreakView(s),
      QuestCelebration q => _QuestView(q),
      LevelUpCelebration l => _LevelUpView(l),
      ReadyCelebration _ => const _ReadyView(),
      HarvestCelebration h => _HarvestView(h),
      PromotionZoneCelebration p => _PromotionView(p),
    };
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(child: body),
    );
  }
}

/// Shared layout: art + text in the middle, actions pinned at the bottom.
class _Frame extends StatelessWidget {
  const _Frame({required this.children, required this.actions, this.burst = true, this.burstColors});
  final List<Widget> children;
  final List<Widget> actions;
  final bool burst;
  final List<Color>? burstColors;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x6, S.x4, S.x6, S.x4),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: children),
                  ),
                ),
              ),
              ...actions.animate(interval: 80.ms, delay: 900.ms).fadeIn(duration: 300.ms).slideY(begin: 0.4, curve: Curves.easeOutCubic),
            ],
          ),
        ),
        if (burst)
          Positioned.fill(
            child: LeafBurst(origin: const Alignment(0, -0.35), colors: burstColors ?? const [C.leaf, C.grassDeep, C.sun, C.flame, C.petalPink, C.sky]),
          ),
      ],
    );
  }
}

Widget _continue(BuildContext context, {String label = 'Continue', ChunkyVariant variant = ChunkyVariant.primary}) =>
    ChunkyButton(label: label, variant: variant, onPressed: () => Navigator.of(context).pop());

// ───────────────────────────── Streak ─────────────────────────────

class _StreakView extends StatefulWidget {
  const _StreakView(this.s);
  final StreakCelebration s;

  @override
  State<_StreakView> createState() => _StreakViewState();
}

class _StreakViewState extends State<_StreakView> {
  bool _bumped = false;

  @override
  void initState() {
    super.initState();
    Sfx.reward(Sound.streak);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _bumped = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.s.days;
    final milestone = isStreakMilestone(days);
    final today = DateTime.now().weekday; // 1 = Mon
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return _Frame(
      burstColors: const [C.flame, C.sun, C.flameLip, C.coral],
      actions: [_continue(context, variant: ChunkyVariant.flame)],
      children: [
        Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Flame(size: 168, flicker: true).animate().scale(begin: const Offset(0.3, 0.3), duration: 600.ms, curve: Curves.elasticOut),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, a) => ScaleTransition(
                  scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                  child: child,
                ),
                child: Text(
                  '${_bumped ? days : days - 1}',
                  key: ValueKey(_bumped),
                  style: T.numXL.copyWith(
                    fontSize: 56,
                    color: Colors.white,
                    shadows: const [Shadow(color: C.flameLip, offset: Offset(0, 3))],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x4),
        Text('day streak!', style: T.h1.copyWith(color: C.flame)).animate().fadeIn(delay: 300.ms),
        const SizedBox(height: S.x6),
        Slab(
          padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 1; i <= 7; i++) _DayDot(label: labels[i - 1], state: i < today ? (today - i < days ? 1 : 0) : (i == today ? (_bumped ? 2 : 3) : 0)),
            ],
          ),
        ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2),
        const SizedBox(height: S.x5),
        Text(
          widget.s.lockUsed
              ? 'A Lid Lock kept your streak safe while you were away.'
              : milestone
              ? '$days days of care! Wren is officially impressed.'
              : 'You looked after the bin today. Come back tomorrow to keep it lit.',
          textAlign: TextAlign.center,
          style: T.body,
        ).animate().fadeIn(delay: 600.ms),
        if (milestone) ...[
          const SizedBox(height: S.x3),
          Tag(
            'Milestone unlocked',
            tone: Tone.flame,
            icon: PhosphorIconsFill.sealCheck,
          ).animate().fadeIn(delay: 800.ms).scale(begin: const Offset(0.6, 0.6), curve: Curves.elasticOut, duration: 700.ms),
        ],
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.label, required this.state});
  final String label;

  /// 0 empty, 1 done, 2 today (lit), 3 today (about to light)
  final int state;

  @override
  Widget build(BuildContext context) {
    final lit = state == 1 || state == 2;
    final dot = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit ? C.flame : C.track,
        border: state == 3 ? Border.all(color: C.flame, width: 2.5) : null,
      ),
      child: lit ? const Icon(PhosphorIconsBold.check, color: Colors.white, size: 18) : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: T.small.copyWith(color: state >= 2 ? C.flame : C.muted, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: S.x2),
        state == 2 ? dot.animate().scale(begin: const Offset(0.5, 0.5), duration: 500.ms, curve: Curves.elasticOut) : dot,
      ],
    );
  }
}

// ───────────────────────────── Quest chest ─────────────────────────────

class _QuestView extends StatefulWidget {
  const _QuestView(this.q);
  final QuestCelebration q;

  @override
  State<_QuestView> createState() => _QuestViewState();
}

class _QuestViewState extends State<_QuestView> with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  int _burst = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      Sfx.reward(Sound.chest);
      _open.forward();
      setState(() => _burst++);
    });
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.q.quest;
    return Stack(
      children: [
        _Frame(
          burst: false,
          actions: [_continue(context, variant: ChunkyVariant.sun)],
          children: [
            Text(widget.q.allDone ? 'All quests done!' : 'Quest complete!', style: T.h1, textAlign: TextAlign.center).animate().fadeIn().slideY(begin: -0.3),
            const SizedBox(height: S.x2),
            Text(q.title, style: T.body, textAlign: TextAlign.center).animate().fadeIn(delay: 150.ms),
            const SizedBox(height: S.x8),
            AnimatedBuilder(
              animation: _open,
              builder: (context, _) => Chest(size: 170, open: Curves.easeOutBack.transform(_open.value)),
            ).animate(onPlay: (c) => c.forward()).shake(hz: 5, offset: const Offset(3, 0), rotation: 0.04, duration: 800.ms, delay: 100.ms),
            const SizedBox(height: S.x6),
            AnimatedBuilder(
              animation: _open,
              builder: (context, _) => Opacity(
                opacity: _open.value,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RewardChip(icon: const AcornIcon(size: 26), text: '+${q.acorns}', tone: Tone.soil),
                    const SizedBox(width: S.x3),
                    _RewardChip(
                      icon: const Icon(PhosphorIconsFill.lightning, color: C.sunLip, size: 26),
                      text: '+${q.xp} XP',
                      tone: Tone.sun,
                    ),
                  ],
                ),
              ),
            ),
            if (widget.q.allDone) ...[
              const SizedBox(height: S.x4),
              Text('Wren\'s bin is in great hands today.', style: T.body, textAlign: TextAlign.center).animate().fadeIn(delay: 1200.ms),
            ],
          ],
        ),
        Positioned.fill(
          child: LeafBurst(
            trigger: _burst,
            count: _burst == 0 ? 0 : 50,
            origin: const Alignment(0, -0.05),
            colors: const [C.sun, C.sunLip, Color(0xFFC07A3A), C.leaf],
          ),
        ),
      ],
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.icon, required this.text, required this.tone});
  final Widget icon;
  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Slab(
      edge: tone.face.withValues(alpha: 0.5),
      color: tone.tint,
      radius: R.button,
      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: S.x2),
          Text(text, style: T.numL.copyWith(fontSize: 22, color: tone.lip)),
        ],
      ),
    );
  }
}

// ───────────────────────────── Level up ─────────────────────────────

class _LevelUpView extends StatefulWidget {
  const _LevelUpView(this.l);
  final LevelUpCelebration l;

  @override
  State<_LevelUpView> createState() => _LevelUpViewState();
}

class _LevelUpViewState extends State<_LevelUpView> {
  @override
  void initState() {
    super.initState();
    Sfx.reward(Sound.xp);
  }

  @override
  Widget build(BuildContext context) {
    return _Frame(
      actions: [_continue(context)],
      children: [
        ProgressRing(
          value: 1,
          size: 190,
          stroke: 16,
          color: C.sun,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('LEVEL', style: T.eyebrow.copyWith(color: C.sunLip)),
              CountUp(widget.l.level, from: widget.l.level - 1, style: T.numXL.copyWith(fontSize: 64)),
            ],
          ),
        ).animate().scale(begin: const Offset(0.4, 0.4), curve: Curves.elasticOut, duration: 900.ms),
        const SizedBox(height: S.x6),
        Text('Level up!', style: T.h1).animate().fadeIn(delay: 300.ms),
        const SizedBox(height: S.x2),
        Text('You\'re now a', style: T.body).animate().fadeIn(delay: 450.ms),
        const SizedBox(height: S.x1),
        Tag(
          widget.l.title,
          tone: Tone.sun,
          icon: PhosphorIconsFill.crown,
        ).animate().fadeIn(delay: 600.ms).scale(begin: const Offset(0.7, 0.7), curve: Curves.elasticOut, duration: 700.ms),
      ],
    );
  }
}

// ───────────────────────────── Compost ready ─────────────────────────────

class _ReadyView extends ConsumerStatefulWidget {
  const _ReadyView();

  @override
  ConsumerState<_ReadyView> createState() => _ReadyViewState();
}

class _ReadyViewState extends ConsumerState<_ReadyView> {
  @override
  void initState() {
    super.initState();
    Sfx.reward(Sound.harvest);
  }

  @override
  Widget build(BuildContext context) {
    final hat = ref.watch(gameProvider.select((g) => g.hat));
    return _Frame(
      burstColors: const [C.soil, C.leaf, C.sun, C.grassDeep],
      actions: [
        ChunkyButton(
          label: 'Harvest now',
          icon: PhosphorIconsFill.basket,
          onPressed: () {
            ref.read(gameProvider.notifier).harvest();
            Navigator.of(context).pop();
          },
        ),
        const SizedBox(height: S.x3),
        ChunkyButton(label: 'Later', variant: ChunkyVariant.white, onPressed: () => Navigator.of(context).pop()),
      ],
      children: [
        Text('YOUR COMPOST IS', style: T.eyebrow.copyWith(color: C.leafLip, fontSize: 14)).animate().fadeIn(),
        const SizedBox(height: S.x2),
        Text(
          'Ready!',
          style: T.display.copyWith(fontSize: 52, color: C.leaf),
        ).animate().scale(begin: const Offset(0.5, 0.5), curve: Curves.elasticOut, duration: 900.ms),
        const SizedBox(height: S.x4),
        Wren(
          mood: WrenMood.thriving,
          size: 190,
          hat: hat,
          ground: true,
          excited: true,
        ).animate().slideY(begin: 0.5, curve: Curves.easeOutBack, duration: 700.ms),
        const SizedBox(height: S.x4),
        Text(
          'Your bottom layer has finished curing. CO₂ is down and its temperature matches the room. It\'s dark, crumbly fertilizer now.',
          textAlign: TextAlign.center,
          style: T.body,
        ).animate().fadeIn(delay: 500.ms),
        const SizedBox(height: S.x2),
        Text('Based on sensor trends, not a lab test.', style: T.small).animate().fadeIn(delay: 700.ms),
      ],
    );
  }
}

// ───────────────────────────── Harvest ─────────────────────────────

class _HarvestView extends ConsumerStatefulWidget {
  const _HarvestView(this.h);
  final HarvestCelebration h;

  @override
  ConsumerState<_HarvestView> createState() => _HarvestViewState();
}

class _HarvestViewState extends ConsumerState<_HarvestView> {
  @override
  void initState() {
    super.initState();
    Sfx.reward(Sound.xp);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.h;
    final harvests = ref.watch(gameProvider.select((g) => g.harvests));
    final saved = h.kg * Impact.dollarsPerKgCompost;
    return _Frame(
      actions: [_continue(context)],
      children: [
        Text('Harvest #$harvests!', style: T.h1).animate().fadeIn().slideY(begin: -0.3),
        const SizedBox(height: S.x2),
        Text('A rare plant sprouted in your garden', style: T.body).animate().fadeIn(delay: 150.ms),
        const SizedBox(height: S.x4),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 170,
              height: 170,
              decoration: const BoxDecoration(color: C.sunTint, shape: BoxShape.circle),
            ),
            Plant(h.plant.species, size: 170, grow: true),
          ],
        ),
        Tag(speciesName(h.plant.species), tone: Tone.flame, icon: PhosphorIconsFill.sparkle).animate().fadeIn(delay: 700.ms),
        const SizedBox(height: S.x6),
        Row(
          children: [
            Expanded(
              child: _StatCard(label: 'Total XP', tone: Tone.sun, icon: PhosphorIconsFill.lightning, value: '+${h.xp}'),
            ),
            const SizedBox(width: S.x2),
            Expanded(
              child: _StatCard(label: 'Compost', tone: Tone.leaf, icon: PhosphorIconsFill.plant, value: '${h.kg.toStringAsFixed(1)}kg'),
            ),
            const SizedBox(width: S.x2),
            Expanded(
              child: _StatCard(label: 'Saved', tone: Tone.sky, icon: PhosphorIconsFill.coins, value: '\$${saved.toStringAsFixed(0)}'),
            ),
          ].animate(interval: 120.ms, delay: 500.ms).fadeIn().slideY(begin: 0.4, curve: Curves.easeOutBack),
        ),
      ],
    );
  }
}

/// Duolingo's lesson-complete stat card: coloured header, white body.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.tone, required this.icon, required this.value});
  final String label;
  final Tone tone;
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: tone.face, borderRadius: BorderRadius.circular(R.button)),
      padding: const EdgeInsets.all(2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(label.toUpperCase(), style: T.eyebrow.copyWith(color: Colors.white, fontSize: 11)),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(R.button - 2)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: tone.face, size: 20),
                const SizedBox(width: 4),
                Flexible(
                  child: FittedBox(
                    child: Text(value, style: T.numM.copyWith(color: tone.lip, fontSize: 19)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Promotion zone ─────────────────────────────

class _PromotionView extends StatefulWidget {
  const _PromotionView(this.p);
  final PromotionZoneCelebration p;

  @override
  State<_PromotionView> createState() => _PromotionViewState();
}

class _PromotionViewState extends State<_PromotionView> {
  @override
  void initState() {
    super.initState();
    Sfx.reward(Sound.xp);
  }

  @override
  Widget build(BuildContext context) {
    final next = (2 + 1).clamp(0, 5);
    return _Frame(
      burstColors: const [C.moss, C.sun, C.leaf],
      actions: [_continue(context, variant: ChunkyVariant.moss)],
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LeagueBadge(2, size: 84).animate().fadeIn().slideX(begin: 0.3),
            const Padding(
                  padding: EdgeInsets.symmetric(horizontal: S.x3),
                  child: Icon(PhosphorIconsBold.caretDoubleRight, color: C.leaf, size: 30),
                )
                .animate(onPlay: (c) => c.repeat())
                .moveX(begin: -4, end: 4, duration: 600.ms, curve: Curves.easeInOut)
                .then()
                .moveX(begin: 4, end: -4, duration: 600.ms),
            LeagueBadge(next, size: 100).animate().scale(begin: const Offset(0.3, 0.3), curve: Curves.elasticOut, duration: 900.ms, delay: 200.ms),
          ],
        ),
        const SizedBox(height: S.x6),
        Text('You\'re #${widget.p.rank}!', style: T.display).animate().fadeIn(delay: 300.ms),
        const SizedBox(height: S.x2),
        Text('Promotion zone unlocked', style: T.h2.copyWith(color: C.leaf)).animate().fadeIn(delay: 450.ms),
        const SizedBox(height: S.x3),
        Text(
          'Finish the week in the top $promoteCount to move up to ${leagueTiers[next].name} League. Keep the bin balanced to hold your spot.',
          style: T.body,
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 600.ms),
      ],
    );
  }
}
