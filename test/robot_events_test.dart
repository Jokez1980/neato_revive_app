import 'package:flutter_test/flutter_test.dart';
import 'package:vacuula/api.dart';
import 'package:vacuula/watcher/robot_events.dart';

RobotStatus g3(int s, int a, {bool ch = false, bool d = false, String? e, String? al}) =>
    RobotStatus.fromGen3({
      'state': s, 'action': a, 'error': e, 'alert': al,
      'details': {'charge': 80, 'isCharging': ch, 'isDocked': d},
    });

void main() {
  test('a full cleaning run gives the expected notifications', () {
    final t = RobotTracker('Kitchen');
    final titles = <String>[];
    for (final s in [
      g3(1, 0, d: true),
      g3(2, 1),
      g3(2, 6, ch: true, d: true),
      g3(2, 1),
      g3(4, 1, e: 'maint_brush_stuck'),
      g3(2, 1, al: 'dustbin_full'),
      g3(2, 4),
      g3(1, 0, d: true, ch: true),
    ]) {
      titles.addAll(t.update(s).map((e) => e.title));
    }
    expect(titles, [
      'Kitchen started cleaning',
      'Kitchen is recharging',
      'Kitchen resumed cleaning',
      'Kitchen needs help',
      'Kitchen',
      'Kitchen finished cleaning',
    ]);
  });

  test('offline is reported once after 3 minutes, then back online', () {
    final t = RobotTracker('Kitchen');
    final t0 = DateTime(2026);
    expect(t.markOnline(false, now: t0), isEmpty);
    expect(t.markOnline(false, now: t0.add(const Duration(minutes: 2))), isEmpty);
    expect(t.markOnline(false, now: t0.add(const Duration(minutes: 3))).single.title, 'Kitchen is offline');
    expect(t.markOnline(false, now: t0.add(const Duration(minutes: 9))), isEmpty);
    expect(t.markOnline(true).single.title, 'Kitchen is back online');
  });
}
