import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// UI sounds + haptics. Every reward moment calls one of these.
enum Sound { tap, great, careful, avoid, xp, streak, chest, harvest, tick }

abstract final class Sfx {
  static final _players = <Sound, AudioPlayer>{};
  static bool enabled = true;

  static Future<void> preload() async {
    for (final s in Sound.values) {
      try {
        final p = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource('sfx/${s.name}.wav'));
        _players[s] = p;
      } catch (_) {
        // Audio is a nicety; never let it break the app.
      }
    }
  }

  static void play(Sound s, {double volume = 1}) {
    if (!enabled) return;
    final p = _players[s];
    if (p == null) return;
    () async {
      try {
        await p.stop();
        await p.setVolume(volume);
        await p.resume();
      } catch (_) {}
    }();
  }

  static void tap() {
    HapticFeedback.lightImpact();
    play(Sound.tap, volume: 0.6);
  }

  static void success() {
    HapticFeedback.mediumImpact();
    play(Sound.great);
  }

  static void reward(Sound s) {
    HapticFeedback.heavyImpact();
    play(s);
  }
}
