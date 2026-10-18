import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Foreground-triggered Android alerts. Background delivery is not implemented.
abstract final class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Future<void>? _initializing;
  static bool _showing = false;

  static const _channel = AndroidNotificationDetails(
    'bin_alerts',
    'Bin alerts',
    channelDescription: 'When your compost is ready, or the bin needs you',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFF58B85C),
  );

  static Future<void> init() => _initializing ??= _init();
  static Future<void> _init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  static Future<void> show(int id, String title, String body) async {
    await init();
    if (!_ready) return;
    if (_showing) return;
    _showing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T').first;
      final countKey = 'notifications.$today.count';
      final sentKey = 'notifications.$today.$id';
      if ((prefs.getInt(countKey) ?? 0) >= 2 || prefs.getBool(sentKey) == true) return;
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _channel),
      );
      await prefs.setInt(countKey, (prefs.getInt(countKey) ?? 0) + 1);
      await prefs.setBool(sentKey, true);
    } catch (e) {
      debugPrint('Notification failed: $e');
    } finally {
      _showing = false;
    }
  }

  static Future<void> streakAtRisk(int days) =>
      show(2, 'Your $days-day streak ends at midnight', 'One quick check on your layers keeps it going.');

  static Future<void> compostReady() =>
      show(1, 'Your compost looks ready', 'Sensor trends suggest the bottom layer may be ready. Check its texture and smell before harvesting.');
}
