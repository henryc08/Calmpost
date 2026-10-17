class CalibrationResult {
  const CalibrationResult({required this.probe, required this.dry, required this.wet, this.readingsRecomputed = 0});
  final int probe, dry, wet, readingsRecomputed;
  factory CalibrationResult.fromJson(Map<String, dynamic> j) => CalibrationResult(
    probe: j['probe'] as int,
    dry: j['moisture_raw_dry'] as int,
    wet: j['moisture_raw_wet'] as int,
    readingsRecomputed: j['readings_recomputed'] as int? ?? 0,
  );
}

String? calibrationError(int probe, int? dry, int? wet) {
  if (probe != 1 && probe != 2) return 'Choose probe 1 or 2.';
  if (dry == null || wet == null || dry < 0 || wet < 0 || dry > 65535 || wet > 65535) return 'Enter whole raw counts from 0 to 65535 for both references.';
  if (dry == wet) return 'Dry and wet counts must be different.';
  return null;
}
