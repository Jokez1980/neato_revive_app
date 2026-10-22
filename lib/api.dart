import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Robotgeneration enligt Vacuula ("neato.gen3" / "neato.gen4").
enum RobotGen { gen3, gen4, unknown }

/// En robot som servern känner till (GET /api/robots).
class RobotInfo {
  RobotInfo({
    required this.serial,
    required this.gen,
    required this.name,
    required this.connected,
    this.labelSerial,
  });

  final String serial;
  final RobotGen gen;
  final String name;
  final bool connected;
  final String? labelSerial;

  factory RobotInfo.fromJson(String serial, Map<String, dynamic> j) {
    final type = j['type'] as String?;
    return RobotInfo(
      serial: serial,
      gen: type == 'neato.gen4'
          ? RobotGen.gen4
          : type == 'neato.gen3'
              ? RobotGen.gen3
              : RobotGen.unknown,
      name: (j['name'] as String?)?.trim().isNotEmpty == true
          ? j['name'] as String
          : serial,
      connected: j['connected'] == true,
      labelSerial: j['label_serial'] as String?,
    );
  }

  String get model => switch (gen) {
        RobotGen.gen3 => 'Neato Gen3',
        RobotGen.gen4 => 'Neato Gen4',
        RobotGen.unknown => 'Unknown model',
      };
}

/// Vilka kommandon roboten accepterar just nu.
class RobotCaps {
  const RobotCaps({
    this.start = false,
    this.stop = false,
    this.pause = false,
    this.resume = false,
    this.base = false,
  });

  final bool start, stop, pause, resume, base;
}

/// Gemensamt format för robotens tillstånd, oavsett generation.
class RobotStatus {
  const RobotStatus({
    required this.state,
    required this.action,
    this.charge,
    this.charging = false,
    this.docked = false,
    this.can = const RobotCaps(),
    this.error,
    this.alert,
    this.manualSupported = false,
  });

  /// idle, busy, paused, error, invalid
  final String state;

  /// cleaning, docking, updating_software, exploring, ...
  final String action;
  final int? charge;
  final bool charging;
  final bool docked;
  final RobotCaps can;
  final String? error;
  final String? alert;

  /// Gen3: the robot offers remote control (availableServices.manualCleaning).
  final bool manualSupported;

  bool get isActive => state == 'busy' || state == 'paused';

  /// Short English label, same names as the Vacuula web app.
  String get label => switch (state) {
        'error' => 'Needs help',
        'paused' => 'Paused',
        'busy' => switch (action) {
            'cleaning' => 'Cleaning',
            'cleaning_standby' => 'Charging during cleaning',
            'docking' => 'Docking',
            'exploring' => 'Exploring map',
            'updating_software' => 'Updating',
            _ => 'Busy',
          },
        _ => charging ? 'Charging' : (docked ? 'Docked' : 'Idle'),
      };

  static int? _int(dynamic v) =>
      v is num ? math.min(100, math.max(0, v.round())) : null;

  factory RobotStatus.fromGen3(Map<String, dynamic> j) {
    const states = {0: 'invalid', 1: 'idle', 2: 'busy', 3: 'paused', 4: 'error'};
    // Samma tolkning som Vacuulas webbapp (app/src/utils/state.ts)
    const actions = {
      1: 'cleaning', // house
      2: 'cleaning', // spot
      3: 'cleaning', // manual
      4: 'docking',
      5: 'diagnostic_test', // user menu active
      6: 'cleaning_standby', // laddar mitt i en städning
      7: 'updating_software',
      8: 'copying_logs',
      9: 'recovering_location',
      11: 'cleaning', // map/zone
      12: 'exploring',
      13: 'acquiring_map_ids',
      14: 'creating_map',
      15: 'exploration_suspended',
    };
    final d = (j['details'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final ac = (j['availableCommands'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return RobotStatus(
      state: states[j['state']] ?? 'invalid',
      action: actions[j['action']] ?? '',
      charge: _int(d['charge']),
      charging: d['isCharging'] == true,
      docked: d['isDocked'] == true,
      can: RobotCaps(
        start: ac['start'] == true,
        stop: ac['stop'] == true,
        pause: ac['pause'] == true,
        resume: ac['resume'] == true,
        base: ac['goToBase'] == true,
      ),
      error: _str(j['error']),
      alert: _str(j['alert']),
      manualSupported: j['availableServices'] is Map &&
          ((j['availableServices'] as Map)['manualCleaning'] is String) &&
          ((j['availableServices'] as Map)['manualCleaning'] as String).isNotEmpty,
    );
  }

  factory RobotStatus.fromGen4(Map<String, dynamic> res) {
    final b = (res['body'] is Map)
        ? (res['body'] as Map).cast<String, dynamic>()
        : res;
    final d = (b['details'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final ac = (b['available_commands'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    // Gen4 reports everything as "errors"; split out the reminders/alerts
    final codes = <String>[
      for (final e in (b['errors'] is List ? b['errors'] as List : const []))
        if (e is Map && e['code'] is String && (e['code'] as String).isNotEmpty) e['code'] as String,
    ];
    const alertCodes = {'dustbin_full', 'brush_change'};
    final alerts = codes.where(alertCodes.contains).toList();
    final errors = codes.where((c) => !alertCodes.contains(c) && c != 'dustbin_emptied').toList();
    final String? error = errors.isEmpty ? null : errors.join(', ');
    final String? alert = alerts.isEmpty ? null : alerts.join(', ');
    return RobotStatus(
      state: (b['state'] as String?) ?? 'invalid',
      action: (b['action'] as String?) ?? '',
      charge: _int(d['charge']),
      charging: d['is_charging'] == true,
      docked: d['is_docked'] == true,
      can: RobotCaps(
        start: ac['start'] == true,
        stop: ac['cancel'] == true,
        pause: ac['pause'] == true,
        resume: ac['resume'] == true,
        base: ac['return_to_base'] == true,
      ),
      error: error,
      alert: alert,
    );
  }

  static String? _str(dynamic v) =>
      (v is String && v.isNotEmpty) ? v : null;
}

enum RobotCommand { start, resume, pause, stop, base, find }

/// Städinställningar som skickas med "Starta".
/// How a cleaning is started - the same choices as the Vacuula web app.
class CleaningPrefs {
  const CleaningPrefs({
    this.gen3Mode = 2,
    this.gen3Nav = 1,
    this.gen3Area = 'map',
    this.spotWidth = 200,
    this.spotHeight = 200,
    this.gen4Mode = 'auto',
    this.gen4Nav = 'normal',
    this.gen4UseMap = true,
  });

  /// Gen3 suction: 1 = Eco, 2 = Turbo (called "Normal" in the Vacuula web app)
  final int gen3Mode;

  /// Gen3 navigation: 1 = Normal, 2 = Extra care, 3 = Deep (Deep needs Turbo suction)
  final int gen3Nav;

  /// Gen3 area: 'map' (uses the map: no-go lines and zones respected, robot must
  /// start from the base), 'house' (everything it can reach, ignores no-go lines)
  /// or 'spot' (a rectangle around the robot).
  final String gen3Area;

  /// Gen3 spot size in cm (100-400)
  final int spotWidth;
  final int spotHeight;

  /// Gen4: eco, turbo, auto, max
  final String gen4Mode;

  /// Gen4: normal, gentle
  final String gen4Nav;

  /// Gen4: use the floorplan in use (no-go lines/zones respected)
  final bool gen4UseMap;

  CleaningPrefs copyWith({
    int? gen3Mode,
    int? gen3Nav,
    String? gen3Area,
    int? spotWidth,
    int? spotHeight,
    String? gen4Mode,
    String? gen4Nav,
    bool? gen4UseMap,
  }) =>
      CleaningPrefs(
        gen3Mode: gen3Mode ?? this.gen3Mode,
        gen3Nav: gen3Nav ?? this.gen3Nav,
        gen3Area: gen3Area ?? this.gen3Area,
        spotWidth: spotWidth ?? this.spotWidth,
        spotHeight: spotHeight ?? this.spotHeight,
        gen4Mode: gen4Mode ?? this.gen4Mode,
        gen4Nav: gen4Nav ?? this.gen4Nav,
        gen4UseMap: gen4UseMap ?? this.gen4UseMap,
      );

  Map<String, dynamic> toJson() => {
        'gen3Mode': gen3Mode,
        'gen3Nav': gen3Nav,
        'gen3Area': gen3Area,
        'spotWidth': spotWidth,
        'spotHeight': spotHeight,
        'gen4Mode': gen4Mode,
        'gen4Nav': gen4Nav,
        'gen4UseMap': gen4UseMap,
      };

  factory CleaningPrefs.fromJson(Map<String, dynamic> j) {
    const d = CleaningPrefs();
    int i(String k, int def, int min, int max) =>
        j[k] is num ? (j[k] as num).toInt().clamp(min, max) : def;
    String s(String k, String def, List<String> ok) => ok.contains(j[k]) ? j[k] as String : def;
    return CleaningPrefs(
      gen3Mode: i('gen3Mode', d.gen3Mode, 1, 2),
      gen3Nav: i('gen3Nav', d.gen3Nav, 1, 3),
      gen3Area: s('gen3Area', d.gen3Area, const ['map', 'house', 'spot']),
      spotWidth: i('spotWidth', d.spotWidth, 100, 400),
      spotHeight: i('spotHeight', d.spotHeight, 100, 400),
      gen4Mode: s('gen4Mode', d.gen4Mode, const ['eco', 'turbo', 'auto', 'max']),
      gen4Nav: s('gen4Nav', d.gen4Nav, const ['normal', 'gentle']),
      gen4UseMap: j['gen4UseMap'] is bool ? j['gen4UseMap'] as bool : d.gen4UseMap,
    );
  }

  /// Gen3 suction actually sent: Deep navigation only works with Turbo suction.
  int get gen3EffectiveMode => gen3Nav == 3 ? 2 : gen3Mode;

  static const gen3ModeNames = {1: 'Eco', 2: 'Turbo'};
  static const gen3NavNames = {1: 'Normal', 2: 'Extra care', 3: 'Deep'};
  static const gen3AreaNames = {'map': 'Map', 'house': 'Whole house', 'spot': 'Spot'};
  static const gen4ModeNames = {'auto': 'Auto', 'eco': 'Eco', 'turbo': 'Turbo', 'max': 'Max'};
  static const gen4NavNames = {'normal': 'Normal', 'gentle': 'Gentle'};

  /// Short summary for the robot card, e.g. "Map · Normal · Deep".
  String summary(RobotGen gen) => gen == RobotGen.gen4
      ? [
          gen4UseMap ? 'Floorplan' : 'Whole home',
          gen4ModeNames[gen4Mode],
          if (gen4Nav != 'normal') gen4NavNames[gen4Nav],
        ].join(' · ')
      : [
          gen3AreaNames[gen3Area],
          if (gen3Area == 'spot') '${spotWidth}x$spotHeight cm',
          gen3ModeNames[gen3EffectiveMode],
          if (gen3Nav != 1) gen3NavNames[gen3Nav],
        ].join(' · ');
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Klient för Vacuula-serverns HTTP-API (samma som Vacuulas egen webbapp använder).
class VacuulaApi {
  VacuulaApi(String baseUrl, {http.Client? client})
      : baseUrl = normalizeUrl(baseUrl),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// "192.168.1.5" -> "http://192.168.1.5"
  static String normalizeUrl(String input) {
    var v = input.trim();
    if (v.isEmpty) return v;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(v)) {
      v = 'http://$v';
    }
    return v.replaceAll(RegExp(r'/+$'), '');
  }

  Uri _u(String path) => Uri.parse('$baseUrl/api$path');

  void close() => _client.close();

  Future<dynamic> _send(Future<http.Response> req, Duration timeout) async {
    final http.Response r;
    try {
      r = await req.timeout(timeout);
    } on TimeoutException {
      throw ApiException('The server did not respond in time');
    } on SocketException {
      throw ApiException('Cannot reach the server');
    } on http.ClientException {
      throw ApiException('Cannot reach the server');
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return data;

    final msg = data is Map && data['error'] is String
        ? data['error'] as String
        : 'HTTP ${r.statusCode}';
    throw ApiException(switch (msg) {
      'Robot not connected' => 'The vacuum is not connected to the server',
      'Robot did not answer in time' => 'The vacuum did not respond in time',
      'Robot not found' => 'The server does not know this robot',
      'Failed to send command to robot' => 'Could not send the command',
      _ => msg,
    });
  }

  /// Generic GET /api{path}.
  Future<dynamic> getJson(String path, {Duration timeout = const Duration(seconds: 15)}) =>
      _send(_client.get(_u(path)), timeout);

  /// Generic POST /api{path} with a JSON body (empty body when null).
  Future<dynamic> postJson(String path, Object? body) => _send(
        _client.post(
          _u(path),
          headers: {'Content-Type': 'application/json'},
          body: body == null ? '' : jsonEncode(body),
        ),
        const Duration(seconds: 25),
      );

  /// GET /api/server – används för att se att adressen verkligen är en Vacuula-server.
  Future<Map<String, dynamic>> serverInfo({Duration timeout = const Duration(seconds: 5)}) async {
    final data = await _send(_client.get(_u('/server')), timeout);
    if (data is Map && data.containsKey('version')) {
      return data.cast<String, dynamic>();
    }
    throw ApiException('The address responds, but it does not look like a Vacuula server');
  }

  /// GET /api/robots
  Future<List<RobotInfo>> robots() async {
    final data = await _send(_client.get(_u('/robots')), const Duration(seconds: 8));
    if (data is! Map) return [];
    return data.entries
        .where((e) => e.value is Map)
        .map((e) => RobotInfo.fromJson(
            e.key as String, (e.value as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /api/robot/{serial}/command
  Future<dynamic> command(String serial, Map<String, dynamic> body) {
    return _send(
      _client.post(
        _u('/robot/${Uri.encodeComponent(serial)}/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
      const Duration(seconds: 20),
    );
  }

  Future<RobotStatus> state(RobotInfo r) async {
    switch (r.gen) {
      case RobotGen.gen3:
        final res = await command(r.serial, {'cmd': 'getRobotState'});
        return RobotStatus.fromGen3((res as Map).cast<String, dynamic>());
      case RobotGen.gen4:
        final res = await command(r.serial, {'ability': 'state.show'});
        return RobotStatus.fromGen4((res as Map).cast<String, dynamic>());
      case RobotGen.unknown:
        throw ApiException('This robot type is not supported');
    }
  }

  /// Kommandon enligt Vacuulas webbapp (app/src/http/gen3.ts och gen4.ts).
  /// [docked]: the robot is on its base (Gen3 "map" cleaning must start from there).
  Future<void> run(RobotInfo r, RobotCommand c, CleaningPrefs p, {bool docked = true}) async {
    final Map<String, dynamic> body;
    if (r.gen == RobotGen.gen3) {
      body = switch (c) {
        RobotCommand.start => {'cmd': 'startCleaning', 'params': gen3StartParams(p, docked: docked)},
        RobotCommand.resume => {'cmd': 'resumeCleaning'},
        RobotCommand.pause => {'cmd': 'pauseCleaning'},
        RobotCommand.stop => {'cmd': 'stopCleaning'},
        RobotCommand.base => {'cmd': 'sendToBase'},
        RobotCommand.find => {'cmd': 'findMe'},
      };
    } else if (r.gen == RobotGen.gen4) {
      body = switch (c) {
        RobotCommand.start => {
            'ability': 'cleaning.start',
            // map: null = clean everything it can reach; with the floorplan in use
            // no-go lines and zones are respected
            'runs': [
              {
                'map': p.gen4UseMap ? await _gen4FloorplanRun(r) : null,
                'settings': {'mode': p.gen4Mode, 'navigation_mode': p.gen4Nav},
              }
            ],
          },
        RobotCommand.resume => {'ability': 'cleaning.resume'},
        RobotCommand.pause => {'ability': 'cleaning.pause'},
        RobotCommand.stop => {'ability': 'cleaning.cancel'},
        RobotCommand.base => {'ability': 'navigation.return_to_base'},
        RobotCommand.find => {'ability': 'utilities.find_me'},
      };
    } else {
      throw ApiException('This robot type is not supported');
    }
    await command(r.serial, body);
  }

  /// Gen3 startCleaning params (category 2 = house, 3 = spot, 4 = map).
  static Map<String, dynamic> gen3StartParams(CleaningPrefs p, {bool docked = true}) {
    final area = (p.gen3Area == 'map' && !docked) ? 'house' : p.gen3Area;
    return {
      'category': switch (area) { 'spot' => 3, 'map' => 4, _ => 2 },
      'mode': p.gen3EffectiveMode,
      'navigationMode': p.gen3Nav,
      if (area == 'spot') ...{'spotWidth': p.spotWidth, 'spotHeight': p.spotHeight},
    };
  }

  /// Gen4: the promoted floorplan to clean with, or null when there is none.
  Future<Map<String, dynamic>?> _gen4FloorplanRun(RobotInfo r) async {
    try {
      final maps = await getJson('/robot/${Uri.encodeComponent(r.serial)}/maps');
      for (final m in (maps is List ? maps : const [])) {
        if (m is Map && m['promoted'] == true && m['id'] is String) {
          return {'rank_id': m['id'], 'track_id': null, 'nogo_enabled': true};
        }
      }
    } catch (_) {}
    return null;
  }
}
