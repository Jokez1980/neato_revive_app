import '../api.dart';

/// Path segment without encoding ':' (the server does not decode paths).
String _seg(String s) => Uri.encodeComponent(s).replaceAll('%3A', ':');

/// One cleaning from GET /api/robot/{serial}/runs, the same data as the
/// "Runs" page in the Vacuula web app (Gen3 and Gen4 have different shapes).
class CleaningRun {
  CleaningRun({
    required this.id,
    required this.start,
    required this.end,
    required this.areaM2,
    required this.batteryUsed,
    required this.complete,
    required this.status,
    this.startedBy,
    this.error,
    this.pickups = 0,
    this.chargeStops = 0,
    this.settings,
  });

  final String id;
  final DateTime? start;
  final DateTime? end;
  final double areaM2;
  final int? batteryUsed;
  final bool complete;

  /// Raw status from the robot, e.g. "complete", "cancelled".
  final String status;
  final String? startedBy;
  final String? error;
  final int pickups;
  final int chargeStops;

  /// e.g. "Turbo · Normal"
  final String? settings;

  Duration? get duration =>
      (start != null && end != null && !end!.isBefore(start!)) ? end!.difference(start!) : null;

  static DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
  static double _num(dynamic v) => v is num ? v.toDouble() : 0;
  static int _int(dynamic v) => v is num ? v.round() : 0;
  static String? _str(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  static const _gen3Modes = {1: 'Eco', 2: 'Turbo'};
  static const _gen3Navs = {1: 'Normal', 2: 'Extra care', 3: 'Deep'};

  factory CleaningRun.fromGen3(Map<String, dynamic> j) {
    final r = (j['run'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final start = r['run_charge_at_start'];
    final end = r['run_charge_at_end'];
    final status = _str(r['status']) ?? 'unknown';
    final mode = _gen3Modes[r['mode']];
    final nav = _gen3Navs[r['navigation_mode']];
    return CleaningRun(
      id: '${j['id'] ?? r['id'] ?? ''}',
      start: _date(r['start_at']),
      end: _date(r['end_at']),
      areaM2: _num(r['cleaned_area']),
      batteryUsed: (start is num && end is num) ? (start - end).round() : null,
      complete: status == 'complete',
      status: status,
      startedBy: _str(r['launched_from']),
      error: _str(r['error']),
      pickups: _int(r['picked_up_count']),
      chargeStops: _int(r['suspended_cleaning_charging_count']),
      settings: [mode, nav].whereType<String>().join(' · ').ifEmpty,
    );
  }

  factory CleaningRun.fromGen4(Map<String, dynamic> j) {
    final timing = (j['timing'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final runs = [
      for (final r in (j['runs'] is List ? j['runs'] as List : const [])) if (r is Map) r.cast<String, dynamic>()
    ];
    var area = 0.0;
    var pickups = 0;
    String? settings;
    for (final r in runs) {
      final stats = (r['stats'] as Map?) ?? const {};
      area += _num(stats['area']);
      pickups += _int(stats['pickup_count']);
      final s = (r['settings'] as Map?) ?? const {};
      settings ??= [_str(s['mode']), _str(s['navigation_mode'])].whereType<String>().map(_cap).join(' · ').ifEmpty;
    }
    final complete = j['cleaning_complete'] == true;
    return CleaningRun(
      id: '${j['id'] ?? ''}',
      start: _date(timing['start']),
      end: _date(timing['end']),
      areaM2: area,
      batteryUsed: j['battery_consumed'] is num ? (j['battery_consumed'] as num).round() : null,
      complete: complete,
      status: complete ? 'complete' : 'not completed',
      startedBy: _str(j['started_by']),
      pickups: pickups,
      chargeStops: _int(timing['charging']),
      settings: settings,
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}

/// Totals over all cleanings the server has recorded.
class CleaningTotals {
  CleaningTotals(List<CleaningRun> runs)
      : count = runs.length,
        completed = runs.where((r) => r.complete).length,
        areaM2 = runs.fold(0.0, (a, r) => a + r.areaM2),
        time = runs.fold(Duration.zero, (a, r) => a + (r.duration ?? Duration.zero)),
        first = runs.map((r) => r.start).whereType<DateTime>().fold<DateTime?>(
            null, (a, d) => a == null || d.isBefore(a) ? d : a);

  final int count;
  final int completed;
  final double areaM2;
  final Duration time;
  final DateTime? first;
}

/// Battery details from the Gen3 command getGeneralInfo.
class BatteryInfo {
  BatteryInfo(this.raw);
  final Map<String, dynamic> raw;

  int? get level => raw['level'] is num ? (raw['level'] as num).round() : null;

  /// Minutes of cleaning left (robot's own estimate), null when unknown/charging.
  int? get timeToEmpty => _positive(raw['timeToEmpty']);

  /// Minutes until fully charged, null when unknown/not charging.
  int? get timeToFullCharge => _positive(raw['timeToFullCharge']);
  int? get totalCharges => raw['totalCharges'] is num ? (raw['totalCharges'] as num).round() : null;
  String? get manufacturingDate => _s(raw['manufacturingDate']);
  String? get vendor => _s(raw['vendor']);

  /// 0 = not authorized, 1 = authorized, 2 = unknown (Neato's codes)
  String? get authorization => switch (raw['authorizationStatus']) {
        0 => 'Not genuine / not authorized',
        1 => 'Genuine',
        2 => 'Unknown',
        _ => null,
      };

  static int? _positive(dynamic v) => v is num && v > 0 ? v.round() : null;
  static String? _s(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : (v is num ? '$v' : null);
}

/// Gen3 serials start with a manufacturing code like "OPS35418": week 35,
/// weekday 4 (1 = Sunday), 2018. Same rule as the Vacuula web app.
DateTime? robotBirthday(String serial) {
  final code = serial.split('-').first;
  final m = RegExp(r'^[A-Z]{3}(\d{2})(\d)(\d{2})$').firstMatch(code);
  if (m == null) return null;
  final week = int.parse(m[1]!), day = int.parse(m[2]!), year = 2000 + int.parse(m[3]!);
  if (week < 1 || week > 53 || day < 1 || day > 7) return null;
  final jan1 = DateTime(year, 1, 1);
  final week1Sunday = jan1.subtract(Duration(days: jan1.weekday % 7)); // weekday: Mon=1..Sun=7
  return DateTime(week1Sunday.year, week1Sunday.month, week1Sunday.day + (week - 1) * 7 + (day - 1));
}

extension RobotDetailsApi on VacuulaApi {
  /// POST /api/robot/{serial} {name}
  Future<void> renameRobot(RobotInfo r, String name) => postJson('/robot/${_seg(r.serial)}', {'name': name.trim()});

  /// GET /api/robot/{serial}/runs, newest first.
  Future<List<CleaningRun>> cleaningRuns(RobotInfo r) async {
    final data = await getJson('/robot/${_seg(r.serial)}/runs');
    final list = [
      for (final e in (data is List ? data : const [])) if (e is Map) e.cast<String, dynamic>()
    ];
    final runs = [
      for (final e in list)
        if (e.containsKey('timing') || r.gen == RobotGen.gen4) CleaningRun.fromGen4(e) else CleaningRun.fromGen3(e)
    ];
    runs.sort((a, b) => (b.start ?? DateTime(0)).compareTo(a.start ?? DateTime(0)));
    return runs;
  }

  /// Gen3 only: battery details (null when the robot does not offer them).
  Future<BatteryInfo?> batteryInfo(RobotInfo r) async {
    if (r.gen != RobotGen.gen3) return null;
    final res = await command(r.serial, {'cmd': 'getGeneralInfo'});
    final data = res is Map ? res['data'] : null;
    final battery = data is Map ? data['battery'] : null;
    return battery is Map ? BatteryInfo(battery.cast<String, dynamic>()) : null;
  }

  /// Gen3: clears the current alert (e.g. "dust bin full").
  Future<void> dismissAlert(RobotInfo r) => command(r.serial, {'cmd': 'dismissCurrentAlert'});
}

// ---------------------------------------------------------------- formatting

String _two(int n) => n.toString().padLeft(2, '0');

String formatDateTime(DateTime? d) =>
    d == null ? '–' : '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

String formatDate(DateTime? d) => d == null ? '–' : '${d.year}-${_two(d.month)}-${_two(d.day)}';

String formatDuration(Duration? d) {
  if (d == null) return '–';
  final h = d.inHours, m = d.inMinutes % 60;
  if (h > 0) return '$h h $m min';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

String formatArea(double m2) => m2 >= 100 ? '${m2.round()} m²' : '${m2.toStringAsFixed(1)} m²';

extension RunMapApi on VacuulaApi {
  /// GET /api/robot/{serial}/run/{id}: the path the robot drove during a
  /// cleaning, as a grid aligned cell-for-cell with that cleaning's floor map
  /// (GET /api/robot/{serial}/maps/{id}). Null when the server has no map for it.
  Future<Map<String, dynamic>?> runPathJson(RobotInfo r, String runId) async {
    try {
      final data = await getJson('/robot/${_seg(r.serial)}/run/${_seg(runId)}');
      return data is Map ? data.cast<String, dynamic>() : null;
    } on ApiException {
      return null; // 404 "Map not found"
    }
  }
}
