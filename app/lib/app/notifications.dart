import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// System notifications in Wren's voice. Android only; a no-op on the web preview.
abstract final class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'bin_alerts',
    'Bin alerts',
    channelDescription: 'When your compost is ready, or the bin needs you',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFF58B85C),
  );

  static Future<void> init() async {
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
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _channel),
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }

  static Future<void> compostReady() => show(1, 'Your compost is ready!', 'Wren says the bottom layer is dark, crumbly and done. Time to harvest.');
}
