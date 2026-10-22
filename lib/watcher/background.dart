import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api.dart';
import '../settings.dart';
import 'robot_events.dart';

const watcherChannelId = 'watch_service';
const statusChannelId = 'robot_status';
const alertsChannelId = 'robot_alerts';
const watcherNotificationId = 888;
const notificationIcon = 'ic_stat_vacuula';

/// Entry point of the Android background service.
/// Runs in its own isolate, also while the app is closed.
@pragma('vm:entry-point')
Future<void> watcherMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings(notificationIcon),
    ),
  );

  var settings = await AppSettings.load();
  if (!settings.notifications || !settings.hasServer) {
    await service.stopSelf();
    return;
  }

  var running = true;
  var api = VacuulaApi(settings.server);
  final trackers = <String, RobotTracker>{};
  final wake = StreamController<void>.broadcast();

  service.on('stop').listen((_) async {
    running = false;
    wake.add(null);
    await service.stopSelf();
  });
  // Settings changed in the app: re-read them and check right away
  service.on('reload').listen((_) async {
    settings = await AppSettings.load();
    if (!settings.notifications || !settings.hasServer) {
      running = false;
      wake.add(null);
      await service.stopSelf();
      return;
    }
    api.close();
    api = VacuulaApi(settings.server);
    trackers.clear();
    wake.add(null);
  });

  var nextId = 1000;
  Future<void> post(RobotEvent e) => notifications.show(
        id: nextId++,
        title: e.title,
        body: e.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            e.important ? alertsChannelId : statusChannelId,
            e.important ? 'Robot needs help' : 'Robot status',
            importance: e.important ? Importance.high : Importance.defaultImportance,
            priority: e.important ? Priority.high : Priority.defaultPriority,
            icon: notificationIcon,
            styleInformation: BigTextStyleInformation(e.body),
          ),
        ),
      );

  Future<void> ongoing(String text) async {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(title: 'Watching your robots', content: text);
    }
  }

  var serverWasOk = true;
  while (running) {
    var busy = false;
    var delay = const Duration(seconds: 15);
    try {
      final robots = await api.robots();
      serverWasOk = true;
      final summary = <String>[];
      for (final r in robots) {
        final t = trackers.putIfAbsent(r.serial, () => RobotTracker(r.name))..name = r.name;
        if (!r.connected) {
          for (final e in t.markOnline(false)) {
            await post(e);
          }
          summary.add('${r.name}: offline');
          continue;
        }
        for (final e in t.markOnline(true)) {
          await post(e);
        }
        final RobotStatus s;
        try {
          s = await api.state(r);
        } catch (_) {
          continue;
        }
        for (final e in t.update(s)) {
          await post(e);
        }
        busy = busy || s.isActive;
        summary.add('${r.name}: ${s.label}${s.charge == null ? '' : ' · ${s.charge}%'}');
      }
      await ongoing(summary.isEmpty ? 'No robots yet' : summary.join(' | '));
    } catch (_) {
      // Normal when the phone is away from home: stay quiet and check less often
      if (serverWasOk) await ongoing("Can't reach the server (away from home?)");
      serverWasOk = false;
      delay = const Duration(seconds: 60);
    }
    if (busy) delay = const Duration(seconds: 5);
    if (!running) break;
    // Sleep, but wake up early on 'reload' / 'stop'
    await Future.any([Future<void>.delayed(delay), wake.stream.first]);
  }
  api.close();
}
