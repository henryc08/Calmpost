import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/layers/layers_screen.dart';
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
}
