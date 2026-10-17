import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/xp_rules.dart';
import '../../state/game.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// Streak calendar: this week by default, the whole month on tap.
/// Consecutive care days join into one amber run.
class StreakCalendar extends StatefulWidget {
  const StreakCalendar({super.key, required this.game});
  final GameState game;

  @override
  State<StreakCalendar> createState() => _StreakCalendarState();
}

class _StreakCalendarState extends State<StreakCalendar> {
  bool _month = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final now = DateTime.now();
    final today = dayOf(now);
    final caredToday = game.caredToday;

    _DayState stateOf(DateTime d, {bool monthView = false}) {
      if (monthView && d.month != now.month) return _DayState.outside;
      if (game.careDays.contains(d)) return _DayState.cared;
      if (game.lockDays.contains(d)) return _DayState.locked;
      if (d == today) return _DayState.today;
      if (d.isAfter(today)) return _DayState.future;
      return _DayState.missed;
    }

    bool joined(_DayState s) => s == _DayState.cared || s == _DayState.locked;

    Widget week(DateTime monday, {bool monthView = false}) => Row(
      children: [
        for (var c = 0; c < 7; c++)
          Expanded(
            child: Builder(
              builder: (context) {
                final d = monday.add(Duration(days: c));
                final st = stateOf(d, monthView: monthView);
                final prev = c > 0 && joined(stateOf(d.subtract(const Duration(days: 1)), monthView: monthView));
                final next = c < 6 && joined(stateOf(d.add(const Duration(days: 1)), monthView: monthView));
                return _Day(date: d, state: st, joinLeft: joined(st) && prev, joinRight: joined(st) && next, isToday: d == today);
              },
            ),
          ),
      ],
    );

    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final first = DateTime(now.year, now.month);
    final firstMonday = first.subtract(Duration(days: first.weekday - 1));
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final rows = (lastDay.difference(firstMonday).inDays ~/ 7) + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('STREAK', style: T.caps)),
            Pressable(
              onTap: () => setState(() => _month = !_month),
              child: Row(
                children: [
                  Text(_month ? _months[now.month - 1] : 'This week', style: T.small.copyWith(color: C.ink2)),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _month ? 0.5 : 0,
                    duration: M.base,
                    child: const Icon(PhosphorIconsRegular.caretDown, size: 13, color: C.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(PhosphorIconsFill.fire, size: 22, color: caredToday ? C.pink : C.faint),
            const SizedBox(width: 6),
            Text('${game.streak.days}', style: T.title.copyWith(fontSize: 30, height: 1)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('day streak', style: T.label.copyWith(color: C.ink2)),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('best ${game.bestStreak} · ${game.streak.lidLocks} Lid Lock', style: T.small),
            ),
          ],
        ),
        const SizedBox(height: S.x4),
        Row(
          children: [
            for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(l, style: T.caps.copyWith(fontSize: 10, color: C.faint)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: M.base,
          curve: M.ease,
          alignment: Alignment.topCenter,
          child: _month
              ? Column(
                  children: [
                    for (var r = 0; r < rows; r++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: week(firstMonday.add(Duration(days: r * 7)), monthView: true),
                      ),
                  ],
                )
              : week(thisMonday),
        ),
        const SizedBox(height: S.x3),
        Text(caredToday ? 'Today counts. See you tomorrow.' : 'Check your layers or follow the next action to keep it going.', style: T.small),
      ],
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
    if (state == _DayState.outside) return const SizedBox(height: 32);
    const size = 30.0;
    const band = C.pinkSoft;
    final (fill, text) = switch (state) {
      _DayState.cared => (C.pink, C.ink),
      _DayState.locked => (C.pinkSoft, C.pinkDeep),
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
        border: isToday && state != _DayState.cared ? Border.all(color: C.ink, width: 1.2) : null,
      ),
      child: state == _DayState.locked
          ? const Icon(PhosphorIconsFill.shieldCheck, size: 13, color: C.pinkDeep)
          : Text(
              '${date.day}',
              style: T.num.copyWith(fontSize: 12, color: text, fontWeight: state == _DayState.cared || isToday ? FontWeight.w800 : FontWeight.w600),
            ),
    );
    if (isToday && state == _DayState.cared) {
      dot = dot.animate().scale(begin: const Offset(0.6, 0.6), duration: 450.ms, curve: Curves.easeOutBack);
    }

    return SizedBox(
      height: 32,
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
