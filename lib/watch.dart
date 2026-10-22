import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'watcher/background.dart';

/// Controls the background watcher that sends notifications when a robot
/// starts, recharges, finishes, needs help or goes offline.
/// The watcher itself lives in watcher/background.dart.
class RobotWatcher {
  /// Background notifications are only available on Android.
  static bool get supported => Platform.isAndroid;

  static bool _configured = false;

  /// Call once at app start.
  static Future<void> init() async {
    if (!supported || _configured) return;
    try {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        watcherChannelId,
        'Background watcher',
        description: 'Shown while Neato Revive App watches your robots',
        importance: Importance.min,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        statusChannelId,
        'Robot status',
        description: 'Started, recharging, paused, finished',
        importance: Importance.defaultImportance,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        alertsChannelId,
        'Robot needs help',
        description: 'Stuck, picked up, dust bin, offline',
        importance: Importance.high,
      ));

      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: watcherMain,
          autoStart: false,
          autoStartOnBoot: true, // the watcher stops itself if notifications are off
          isForegroundMode: true,
          notificationChannelId: watcherChannelId,
          initialNotificationTitle: 'Watching your robots',
          initialNotificationContent: 'Starting…',
          foregroundServiceNotificationId: watcherNotificationId,
          foregroundServiceTypes: [AndroidForegroundType.specialUse],
        ),
        iosConfiguration: IosConfiguration(autoStart: false),
      );
      _configured = true;
    } catch (_) {
      // Plugins missing or misconfigured: the app works, just without notifications
    }
  }

  /// Asks for the notification permission (Android 13+). Returns true if granted.
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Starts, reloads or stops the watcher to match the settings.
  static Future<void> apply({required bool enabled, required String server}) async {
    if (!supported) return;
    await init();
    if (!_configured) return;
    final service = FlutterBackgroundService();
    try {
      final running = await service.isRunning();
      if (enabled && server.isNotEmpty) {
        if (running) {
          service.invoke('reload');
        } else {
          await service.startService();
        }
      } else if (running) {
        service.invoke('stop');
      }
    } catch (_) {
      // ignore - see init()
    }
  }
}
