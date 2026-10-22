import '../api.dart';

/// Monday-first week for display. Values are minutes since midnight etc.
const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Gen3 robots number days Sunday = 0 … Saturday = 6.
int gen3DayToIndex(int d) => (d + 6) % 7; // -> Monday = 0
int indexToGen3Day(int i) => (i + 1) % 7;

/// Gen4 robots use 'mon' … 'sun'.
const gen4Days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

int? parseHHMM(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

String formatHHMM(int minutes) {
  final m = ((minutes % 1440) + 1440) % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Moves a weekly slot (day index Monday=0, "HH:MM") by [delta] minutes,
/// changing the day when it crosses midnight. Same as the Vacuula web app.
({int day, String time}) shiftSlot(int day, String time, int delta) {
  final m = parseHHMM(time);
  if (m == null) return (day: day, time: time);
  final total = m + delta;
  final dayShift = (total / 1440).floor();
  return (day: (((day + dayShift) % 7) + 7) % 7, time: formatHHMM(total));
}

/// "Mon, Wed, Fri" / "Every day" / "Weekdays" / "Weekends"
String daysLabel(Iterable<int> days) {
  final s = days.toSet();
  if (s.length == 7) return 'Every day';
  if (s.length == 5 && !s.contains(5) && !s.contains(6)) return 'Weekdays';
  if (s.length == 2 && s.contains(5) && s.contains(6)) return 'Weekends';
  return (s.toList()..sort()).map((d) => weekdayShort[d]).join(', ');
}

// ------------------------------------------------------------------ Gen3

/// One Gen3 schedule event. The robot keeps its clock in UTC, so [utcDay] and
/// [utcTime] are UTC; use [localDay]/[localTime] for display.
class Gen3Event {
  Gen3Event(this.raw);

  final Map<String, dynamic> raw;

  int get utcDay => gen3DayToIndex((raw['day'] as num?)?.toInt() ?? 0);
  String get utcTime => (raw['startTime'] as String?) ?? '00:00';

  /// 1 = Eco, 2 = Normal
  int get mode => (raw['mode'] as num?)?.toInt() ?? 2;

  /// Zone (boundary) this event cleans, if any.
  String? get boundaryId {
    final id = raw['boundaryId'];
    if (id is String && id.isNotEmpty) return id;
    final b = raw['boundary'];
    if (b is Map && b['id'] is String && (b['id'] as String).isNotEmpty) return b['id'] as String;
    return null;
  }

  String? get boundaryName {
    final b = raw['boundary'];
    return (b is Map && b['name'] is String) ? b['name'] as String : null;
  }

  ({int day, String time}) local(int offsetMinutes) => shiftSlot(utcDay, utcTime, offsetMinutes);

  /// Builds an event from local (phone) time.
  static Gen3Event fromLocal({
    required int day,
    required String time,
    required int mode,
    required int offsetMinutes,
    String? boundaryId,
  }) {
    final utc = shiftSlot(day, time, -offsetMinutes);
    return Gen3Event({
      'mode': mode,
      'day': indexToGen3Day(utc.day),
      'startTime': utc.time,
      if (boundaryId != null) 'boundaryId': boundaryId,
    });
  }

  /// What the robot expects in setSchedule: mode, day, startTime and boundaryId.
  Map<String, dynamic> toRobot() {
    final m = Map<String, dynamic>.from(raw)..remove('boundary');
    final id = boundaryId;
    if (id != null) {
      m['boundaryId'] = id;
    } else {
      m.remove('boundaryId');
    }
    return m;
  }
}

class Gen3Schedule {
  Gen3Schedule(this.enabled, this.events);
  final bool enabled;
  final List<Gen3Event> events;
}

// ------------------------------------------------------------------ Gen4

class Gen4Event {
  Gen4Event(this.raw);

  final Map<String, dynamic> raw;

  String? get id => raw['id'] as String?;
  bool get enabled => raw['enabled'] != false;
  String get time => (raw['time'] as String?) ?? '00:00';
  List<int> get days => [
        for (final d in (raw['days'] as List? ?? const []))
          if (gen4Days.contains(d)) gen4Days.indexOf(d as String),
      ];

  List<Map<String, dynamic>> get _runs {
    final c = raw['command'];
    final runs = (c is Map) ? c['runs'] : null;
    return [for (final r in (runs is List ? runs : const [])) if (r is Map) r.cast<String, dynamic>()];
  }

  String get mode {
    final r = _runs;
    final s = r.isEmpty ? null : r.first['settings'];
    return (s is Map ? s['mode'] as String? : null) ?? 'auto';
  }

  String get navigation {
    final r = _runs;
    final s = r.isEmpty ? null : r.first['settings'];
    return (s is Map ? s['navigation_mode'] as String? : null) ?? 'normal';
  }

  /// Floorplan used, or null for "clean everything".
  String? get mapId {
    final r = _runs;
    final m = r.isEmpty ? null : r.first['map'];
    return m is Map ? m['rank_id'] as String? : null;
  }

  List<String> get zoneIds => [
        for (final r in _runs)
          if (r['map'] is Map && (r['map'] as Map)['track_id'] is String) (r['map'] as Map)['track_id'] as String,
      ];

  static Gen4Event build({
    String? id,
    required bool enabled,
    required List<int> days,
    required String time,
    required String mode,
    required String navigation,
    String? mapId,
    List<String> zoneIds = const [],
    bool nogo = true,
  }) {
    final settings = {'mode': mode, 'navigation_mode': navigation};
    final runs = mapId == null
        ? [
            {'map': null, 'settings': settings}
          ]
        : zoneIds.isEmpty
            ? [
                {
                  'map': {'rank_id': mapId, 'track_id': null, 'nogo_enabled': nogo},
                  'settings': settings
                }
              ]
            : [
                for (final z in zoneIds)
                  {
                    'map': {'rank_id': mapId, 'track_id': z, 'nogo_enabled': nogo},
                    'settings': settings
                  }
              ];
    return Gen4Event({
      if (id != null) 'id': id,
      'enabled': enabled,
      'days': [for (final d in (days.toSet().toList()..sort())) gen4Days[d]],
      'time': time,
      'command': {
        'ability': 'cleaning.start',
        'auto_localization': false,
        'force_floorplan': false,
        'runs': runs,
      },
    });
  }
}

class Gen4Schedule {
  Gen4Schedule(this.enabled, this.events);
  final bool enabled;
  final List<Gen4Event> events;
}

// ------------------------------------------------------------------ API

/// Schedule commands, same as the Vacuula web app (app/src/http/gen3.ts, gen4.ts).
extension ScheduleApi on VacuulaApi {
  Future<Gen3Schedule> gen3Schedule(RobotInfo r) async {
    final res = await command(r.serial, {'cmd': 'getSchedule'});
    final d = (res is Map && res['data'] is Map) ? (res['data'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    return Gen3Schedule(
      d['enabled'] == true,
      [for (final e in (d['events'] is List ? d['events'] as List : const [])) if (e is Map) Gen3Event(e.cast<String, dynamic>())],
    );
  }

  /// Replaces all Gen3 events (that is how the robot wants it).
  Future<void> setGen3Events(RobotInfo r, List<Gen3Event> events) async {
    final res = await command(r.serial, {
      'cmd': 'setSchedule',
      'params': {'events': [for (final e in events) e.toRobot()]},
    });
    _checkGen3(res);
  }

  Future<void> setGen3ScheduleEnabled(RobotInfo r, bool on) async {
    final res = await command(r.serial, {'cmd': on ? 'enableSchedule' : 'disableSchedule'});
    _checkGen3(res);
  }

  void _checkGen3(dynamic res) {
    if (res is Map && res['result'] != null && res['result'] != 'ok') {
      throw ApiException('The robot did not accept the change (${res['result']})');
    }
  }

  Future<Gen4Schedule> gen4Schedule(RobotInfo r) async {
    final res = await command(r.serial, {'ability': 'scheduling.show'});
    final b = (res is Map && res['body'] is Map) ? (res['body'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    return Gen4Schedule(
      b['enabled'] != false,
      [for (final e in (b['events'] is List ? b['events'] as List : const [])) if (e is Map) Gen4Event(e.cast<String, dynamic>())],
    );
  }

  /// Adds (no id) or updates (with id) one Gen4 event.
  Future<void> saveGen4Event(RobotInfo r, Gen4Event e) =>
      command(r.serial, {'ability': 'scheduling.update', 'event': e.raw});

  Future<void> deleteGen4Event(RobotInfo r, String id) =>
      command(r.serial, {'ability': 'scheduling.delete', 'id': id});
}
