import 'dart:convert';
import 'dart:io';
import 'package:calmpost/data/food_catalog.dart';
import 'package:calmpost/domain/advice_rules.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/domain/trunc_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

BinSnapshot caseSnapshot(Map<String, dynamic> c) => BinSnapshot(
  time: DateTime.now(),
  topMoisture: (c['top'] as num?)?.toDouble() ?? 0,
  bottomMoisture: (c['bottom'] as num?)?.toDouble() ?? 0,
  topMeasured: c['top'] != null,
  bottomMeasured: c['bottom'] != null,
  topTemp: 21 + (c['delta'] as num? ?? 14).toDouble(),
  bottomTemp: 0,
  bottomTemperatureMeasured: false,
  co2: 2400,
  ambientTemp: 21,
  co2SlopePerDay: (c['slope'] as num? ?? -2).toDouble(),
  greens7d: (c['greens'] as num).toDouble(),
  browns7d: (c['browns'] as num).toDouble(),
  topStage: Stage.active,
  bottomStage: Stage.curing,
  healthyHoursToday: 2,
  stale: c['stale'] == true,
  bottomMoistureCalibrated: true,
);

void main() {
  final cases = (jsonDecode(File('../testdata/trunc_cases.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  for (final c in cases) {
    test('shared decisions: ${c['name']}', () {
      final s = caseSnapshot(c);
      expect(needFor(s).name, c['need']);
      final a = guidanceFor(s);
      expect(a.status, c['status']);
      expect(truncMaterialAnswer(s, 'apples', foodCatalog), contains(c['apple']));
      if (a.status == 'unknown') expect(a.usable, false);
    });
  }
  test('dry balanced scrap check does not claim missing nitrogen', () {
    final a = adviseFor(foodById['apple_core']!, caseSnapshot(cases[1]), foodById);
    expect(a.verdict, Verdict.careful);
    expect(a.reason, contains('water'));
  });
  test('material extraction and keep-outs do not depend on a model', () {
    expect(truncRequestedItem('Should I add more apples to this compost?'), 'apples');
    expect(truncRequestedItem('What about apples?'), 'apples');
    expect(truncRequestedItem('How is my compost doing?'), isNull);
    expect(truncMaterialAnswer(caseSnapshot(cases[1]), 'water', foodCatalog), contains('Water fits'));
    expect(truncFollowupItem('And how much?', const [TruncTurn(role: TruncRole.user, text: 'Should I add apples?')]), 'apples');
    expect(truncMaterialAnswer(caseSnapshot(cases.first), 'apples and cheese', foodCatalog), contains('Keep'));
    expect(truncMaterialAnswer(caseSnapshot(cases.first), 'mystery polymer', foodCatalog), contains('cannot confidently identify'));
  });
}
