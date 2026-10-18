import 'package:calmpost/domain/xp_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final evening = DateTime(2026, 10, 17, 20);
  final yesterday = DateTime(2026, 10, 16, 9);

  StreakState s({int days = 6, DateTime? last}) => StreakState(days: days, lidLocks: 0, lastCareDay: last);

  test('at risk in the evening when the last care was yesterday', () {
    expect(streakAtRisk(s(last: yesterday), evening), isTrue);
  });

  test('not before 6 pm', () {
    expect(streakAtRisk(s(last: yesterday), DateTime(2026, 10, 17, 17, 59)), isFalse);
    expect(streakAtRisk(s(last: yesterday), DateTime(2026, 10, 17, 18)), isTrue);
  });

  test('not once today is cared for', () {
    expect(streakAtRisk(s(last: DateTime(2026, 10, 17, 8)), evening), isFalse);
  });

  test('not when there is no streak to lose', () {
    expect(streakAtRisk(s(days: 0, last: yesterday), evening), isFalse);
    expect(streakAtRisk(s(last: null), evening), isFalse);
    expect(streakAtRisk(s(last: DateTime(2026, 10, 14)), evening), isFalse, reason: 'already broken');
  });
}
