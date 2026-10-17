import 'dart:math' as math;

import 'models.dart';

/// Bin Health Score, 0–100. Deterministic and explainable.
///
///   health = 0.45·moisture + 0.20·temperature + 0.15·co2 + 0.20·balance
///
/// Moisture is weighted highest because it's our most reliable sensor.
class HealthBreakdown {
  const HealthBreakdown({required this.moisture, required this.temperature, required this.co2, required this.balance});

  final double moisture;
  final double temperature;
  final double co2;
  final double balance;

  static const wMoisture = 0.45;
  static const wTemperature = 0.20;
  static const wCo2 = 0.15;
  static const wBalance = 0.20;

  int get total => (moisture * wMoisture + temperature * wTemperature + co2 * wCo2 + balance * wBalance).round().clamp(0, 100);
}

/// 100 inside [lo, hi], falling linearly to 0 at [falloff] outside the band.
double bandScore(double v, double lo, double hi, double falloff) {
  if (v >= lo && v <= hi) return 100;
  final d = v < lo ? lo - v : v - hi;
  return math.max(0, 100 - d / falloff * 100);
}

const moistureLo = 40.0;
const moistureHi = 60.0;

HealthBreakdown computeHealth(BinSnapshot s) {
  // An unmeasured layer is left out rather than scored.
  final topM = bandScore(s.topMoisture, moistureLo, moistureHi, 25);
  final moisture = s.bottomMeasured ? (topM + bandScore(s.bottomMoisture, moistureLo, moistureHi, 25)) / 2 : topM;

  final topDelta = s.topTemp - s.ambientTemp;
  final bottomDelta = s.bottomTemp - s.ambientTemp;
  final topT = bandScore(topDelta, 5, 25, 10);
  final bottomCuring = s.bottomStage.index >= Stage.curing.index;
  final bottomT = bottomCuring ? bandScore(bottomDelta, -2, 8, 10) : bandScore(bottomDelta, 3, 25, 10);
  final temperature = s.bottomMeasured ? (topT + bottomT) / 2 : topT;

  final active = s.topStage == Stage.active || s.topStage == Stage.hot;
  final activityScore = active ? bandScore(s.co2, 900, 6000, 900) : 100.0;
  final trendScore = bottomCuring ? (s.co2SlopePerDay <= 2 ? 100.0 : math.max(0.0, 100 - s.co2SlopePerDay * 10)) : 100.0;
  final co2 = (activityScore + trendScore) / 2;

  final ratio = s.greens7d <= 0 ? 4.0 : s.browns7d / s.greens7d;
  final balance = bandScore(ratio, 1.6, 3.4, 1.4);

  return HealthBreakdown(moisture: moisture, temperature: temperature, co2: co2, balance: balance);
}

Balance balanceOf(BinSnapshot s) {
  final ratio = s.greens7d <= 0 ? 4.0 : s.browns7d / s.greens7d;
  if (s.topMoisture > 64 || ratio < 1.2) return Balance.needsBrowns;
  if (s.topMoisture < 36 || ratio > 4) return Balance.needsGreens;
  return Balance.balanced;
}

BinMood moodFor(BinSnapshot s, int health) {
  if (s.topMoisture > 66) return BinMood.wet;
  if (s.topMoisture < 33) return BinMood.dry;
  if (health >= 85) return BinMood.thriving;
  if (health >= 70) return BinMood.healthy;
  if (health >= 50) return BinMood.fair;
  return BinMood.struggling;
}

String moodLabel(BinMood m) => switch (m) {
  BinMood.thriving => 'Thriving',
  BinMood.healthy => 'Healthy',
  BinMood.fair => 'Fair',
  BinMood.dry => 'Too dry',
  BinMood.wet => 'Too wet',
  BinMood.struggling => 'Needs care',
};

/// Health state of a single zone, for tinting the bin illustration.
/// `unknown`: no sensor in that zone.
enum ZoneState { good, wet, dry, cold, hot, unknown }

ZoneState zoneState(BinSnapshot s, Zone z) {
  if (z == Zone.air) return s.co2 > 7000 ? ZoneState.hot : ZoneState.good;
  if (z == Zone.bottom && !s.bottomMeasured) return ZoneState.unknown;
  final m = s.moisture(z);
  if (m > moistureHi + 4) return ZoneState.wet;
  if (m < moistureLo - 4) return ZoneState.dry;
  return ZoneState.good;
}
