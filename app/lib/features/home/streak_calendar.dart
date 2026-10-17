import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// The month at a glance: care days joined into streak runs.
class StreakCalendar extends StatelessWidget {
  const StreakCalendar({super.key, required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dayOf(now);
    final first = DateTime(now.year, now.month);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday-first grid
    final rows = ((lead + daysInMonth) / 7).ceil();
    final caredToday = game.caredToday;
    final days = game.streak.days;

    _DayState stateOf(DateTime d) {
      if (d.month != now.month) return _DayState.outside;
      if (game.careDays.contains(d)) return _DayState.cared;
      if (game.lockDays.contains(d)) return _DayState.locked;
      if (d == today) return _DayState.today;
      if (d.isAfter(today)) return _DayState.future;
      return _DayState.missed;
    }

    bool joined(_DayState s) => s == _DayState.cared || s == _DayState.locked;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: caredToday ? C.amber : C.amberSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(PhosphorIconsFill.fire, color: caredToday ? Colors.white : C.amber, size: 21),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$days day streak', style: T.title),
                    const SizedBox(height: 2),
                    Text('Best ${game.bestStreak} · ${game.streak.lidLocks} Lid Lock${game.streak.lidLocks == 1 ? '' : 's'}', style: T.small),
                  ],
                ),
              ),
              caredToday
                  ? const Badge2('Done today', color: C.leaf, background: C.leafSoft, icon: PhosphorIconsBold.check)
                  : const Badge2('Not yet today', color: C.amber, background: C.amberSoft),
            ],
          ),
          const SizedBox(height: S.x5),
          Row(
            children: [
              Expanded(child: Text('${_months[now.month - 1]} ${now.year}', style: T.heading.copyWith(fontSize: 14))),
              Text('${game.careDays.where((d) => d.month == now.month && d.year == now.year).length} care days', style: T.small),
            ],
          ),
          const SizedBox(height: S.x3),
          Row(
            children: [
              for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(l, style: T.caps.copyWith(fontSize: 10.5, color: C.faint)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.x2),
          for (var r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final d = first.add(Duration(days: r * 7 + c - lead));
                          final st = stateOf(d);
                          final prev = c > 0 && joined(stateOf(d.subtract(const Duration(days: 1))));
                          final next = c < 6 && joined(stateOf(d.add(const Duration(days: 1))));
                          return _Day(date: d, state: st, joinLeft: joined(st) && prev, joinRight: joined(st) && next, isToday: d == today);
                        },
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: S.x4),
          const Hairline(),
          const SizedBox(height: S.x3),
          Row(
            children: [
              const Icon(PhosphorIconsRegular.shieldCheck, size: 16, color: C.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  caredToday ? 'Streak safe for today. See you tomorrow.' : 'Check your layers or follow the next action to keep it going.',
                  style: T.small,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _DayState { outside, cared, locked, today, missed, future }

class _Day extends StatelessWidget {
  const _Day({required this.date, required this.state, required this.joinLeft, required this.joinRight, required this.isToday});
  final DateTime date;
  final _DayState state;
  final bool joinLeft;
  final bool joinRight;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    if (state == _DayState.outside) return const SizedBox(height: 34);
    const size = 32.0;
    const band = C.amberSoft;
    final (fill, text) = switch (state) {
      _DayState.cared => (C.amber, Colors.white),
      _DayState.locked => (C.amberSoft, C.amber),
      _DayState.today => (Colors.transparent, C.ink),
      _DayState.missed => (Colors.transparent, C.muted),
      _ => (Colors.transparent, C.faint),
    };

    Widget dot = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: isToday ? Border.all(color: state == _DayState.cared ? C.amber : C.ink, width: 1.5) : null,
      ),
      child: state == _DayState.locked
          ? const Icon(PhosphorIconsFill.shieldCheck, size: 14, color: C.amber)
          : Text(
              '${date.day}',
              style: T.num.copyWith(fontSize: 12.5, color: text, fontWeight: state == _DayState.cared || isToday ? FontWeight.w800 : FontWeight.w600),
            ),
    );
    if (isToday && state == _DayState.cared) {
      dot = dot.animate().scale(begin: const Offset(0.6, 0.6), duration: 500.ms, curve: Curves.easeOutBack);
    }

    return SizedBox(
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(height: size, color: joinLeft ? band : Colors.transparent),
              ),
              Expanded(
                child: Container(height: size, color: joinRight ? band : Colors.transparent),
              ),
            ],
          ),
          dot,
        ],
      ),
    );
  }
}
