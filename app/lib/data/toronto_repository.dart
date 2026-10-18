import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/toronto.dart';

/// A reviewed, bundled City-data snapshot: works with mock/live bins and offline.
class TorontoRepository {
  Future<TorontoData> load() async => TorontoData.fromJson(
    jsonDecode(await rootBundle.loadString('assets/data/toronto_waste.json'))
        as Map<String, dynamic>,
  );
}

class TorontoProgressStore {
  TorontoProgressStore(this.preferences, this.scope);
  final SharedPreferences? preferences;
  final String scope;
  String get key =>
      'calmpost.toronto.learning.v1.${Uri.encodeComponent(scope)}';
  TorontoProgress read() {
    final raw = preferences?.getString(key);
    if (raw == null) return TorontoProgress();
    // Corruption is surfaced with recovery instead of silently replacing evidence.
    return TorontoProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> write(TorontoProgress progress) async {
    if (preferences == null) throw StateError('Local storage unavailable');
    if (!await preferences!.setString(key, jsonEncode(progress.toJson()))) {
      throw StateError('Local save failed');
    }
  }

  Future<void> reset() async {
    if (preferences == null || !await preferences!.remove(key)) {
      throw StateError('Local reset failed');
    }
  }
}
