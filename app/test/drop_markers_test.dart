import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/layers/layers_screen.dart';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/state/game.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clock time reads like "2:14 pm"', () {
    expect(clockTime(DateTime(2026, 10, 17, 14, 14)), '2:14 pm');
    expect(clockTime(DateTime(2026, 10, 17, 0, 5)), '12:05 am');
    expect(clockTime(DateTime(2026, 10, 17, 12, 0)), '12:00 pm');
  });

  test('log entries default to manual', () {
    expect(LogSource.values, [LogSource.manual, LogSource.camera]);
  });

  test('reviewed camera drops are logged as camera, typed logs as manual', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    final peel = Advice(item: foodById['banana_peel']!, verdict: Verdict.great, headline: '', reason: '');
    game.recordDrop([peel], added: const [true], suggestedIds: const []);
    expect(c.read(gameProvider).logs.first.source, LogSource.camera);
    game.recordLog(peel, added: true, suggestedIds: const []);
    expect(c.read(gameProvider).logs.first.source, LogSource.manual);
  });
}
