import 'dart:math' as math;
import 'dart:typed_data';

import '../api.dart';

/// A point in normalised map coordinates (0..1 across width and height),
/// the same coordinate system the robot and the Vacuula web app use.
typedef MapPoint = ({double x, double y});

/// One saved map ("persistent map" on Gen3, "floorplan" on Gen4).
class RobotMap {
  RobotMap(this.raw);

  /// Everything the server sent, kept so nothing is lost when saving.
  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get name {
    final n = (raw['name'] as String?)?.trim() ?? '';
    return n.isEmpty || n == '(unnamed)' ? 'Unnamed map' : n;
  }

  String get rawName => (raw['name'] as String?) ?? '';

  /// Gen3: map can be turned on/off.
  bool? get enabled => raw['enabled'] is bool ? raw['enabled'] as bool : null;

  /// Gen4: the floorplan the robot currently uses.
  bool? get promoted => raw['promoted'] is bool ? raw['promoted'] as bool : null;

  DateTime? get created {
    final s = (raw['created_at'] as String?) ?? id;
    return DateTime.tryParse(s)?.toLocal();
  }

  /// Dock position in normalised coordinates, if known.
  MapPoint? get base {
    final b = raw['base'];
    // Gen4: [x_mm, y_mm, dir] in the map frame + origin/resolution/imgsize
    if (raw['origin'] is List && raw['resolution'] is num && raw['imgsize'] is List && b is List && b.length >= 2) {
      const noBase = 2147483647;
      if (b[0] == noBase || b[1] == noBase) return null;
      final o = raw['origin'] as List, size = raw['imgsize'] as List;
      final res = (raw['resolution'] as num).toDouble();
      return (
        x: (((b[0] as num) - (o[0] as num)) / res) / (size[0] as num),
        y: (((b[1] as num) - (o[1] as num)) / res) / (size[1] as num),
      );
    }
    // Gen3: [x, y] already normalised (or {x, y})
    if (b is List && b.length >= 2 && b[0] is num && b[1] is num) {
      return (x: (b[0] as num).toDouble(), y: (b[1] as num).toDouble());
    }
    if (b is Map && b['x'] is num && b['y'] is num) {
      return (x: (b['x'] as num).toDouble(), y: (b['y'] as num).toDouble());
    }
    return null;
  }
}

/// The occupancy grid of a map.
class MapGrid {
  MapGrid(this.width, this.height, this.cells, {this.base});

  final int width;
  final int height;

  /// Row-major cells: 0 = unexplored, 1 = floor, anything else = wall/obstacle.
  final Uint8List cells;
  final MapPoint? base;

  /// Decodes the server's run-length encoded map: rle = [[value, count], ...].
  factory MapGrid.fromJson(Map<String, dynamic> j) {
    final w = (j['width'] as num).toInt();
    final h = (j['height'] as num).toInt();
    final cells = Uint8List(w * h);
    var i = 0;
    for (final run in (j['rle'] as List? ?? const [])) {
      if (run is! List || run.length < 2) continue;
      final v = (run[0] as num).toInt();
      final n = (run[1] as num).toInt();
      final end = math.min(i + n, cells.length);
      if (v != 0) cells.fillRange(i, end, v.clamp(0, 255));
      i = end;
      if (i >= cells.length) break;
    }
    MapPoint? base;
    final b = j['base'];
    if (b is List && b.length >= 2 && b[0] is num && b[1] is num) {
      base = (x: (b[0] as num).toDouble(), y: (b[1] as num).toDouble());
    }
    return MapGrid(w, h, cells, base: base);
  }

  /// Bounding box (in cells) of the explored floor, for zooming to fit.
  ({int minX, int minY, int maxX, int maxY})? contentBounds() {
    var minX = width, minY = height, maxX = -1, maxY = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (cells[row + x] != 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < minX) return null;
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}

enum BoundaryKind { noGoLine, zone, noGoZone }

/// A no-go line or a zone. Keeps the robot's original JSON so unknown fields survive a save.
class Boundary {
  Boundary(this.raw);

  factory Boundary.create({
    required String name,
    required String color,
    required List<MapPoint> vertices,
    required bool polygon,
    String? function,
  }) =>
      Boundary({
        'id': newId(),
        'name': name,
        'color': color,
        'type': polygon ? 'polygon' : 'polyline',
        'vertices': [for (final p in vertices) [p.x, p.y]],
        'enabled': true,
        if (function != null) 'function': function,
      });

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get name => (raw['name'] as String?) ?? '';
  String get color => (raw['color'] as String?) ?? '#ff7a45';
  bool get isPolygon => raw['type'] == 'polygon';
  bool get enabled => raw['enabled'] != false;

  /// Gen4 only: 'cleaning' or 'nogo'.
  String? get function => raw['function'] as String?;

  BoundaryKind get kind => !isPolygon
      ? BoundaryKind.noGoLine
      : (function == 'nogo' ? BoundaryKind.noGoZone : BoundaryKind.zone);

  String get kindLabel => switch (kind) {
        BoundaryKind.noGoLine => 'No-go line',
        BoundaryKind.noGoZone => 'No-go zone',
        BoundaryKind.zone => function == 'cleaning' ? 'Cleaning zone' : 'Zone',
      };

  /// No-go lines and no-go zones can be switched on/off; cleaning zones can be cleaned.
  bool get canToggle => kind != BoundaryKind.zone;
  bool get canClean => kind == BoundaryKind.zone;

  List<MapPoint> get vertices => [
        for (final v in (raw['vertices'] as List? ?? const []))
          if (v is List && v.length >= 2) (x: (v[0] as num).toDouble(), y: (v[1] as num).toDouble()),
      ];

  Boundary copyWith({String? name, String? color, bool? enabled, List<MapPoint>? vertices, bool? polygon, String? function}) {
    final m = Map<String, dynamic>.from(raw);
    if (name != null) m['name'] = name;
    if (color != null) m['color'] = color;
    if (enabled != null) m['enabled'] = enabled;
    if (vertices != null) m['vertices'] = [for (final p in vertices) [p.x, p.y]];
    if (polygon != null) m['type'] = polygon ? 'polygon' : 'polyline';
    if (function != null) m['function'] = function;
    if (m['type'] != 'polygon') m.remove('relevancy');
    return Boundary(m);
  }

  /// JSON for the robot. Gen3 polygons need a "relevancy" point (the centroid).
  Map<String, dynamic> toGen3Json() {
    final m = Map<String, dynamic>.from(raw);
    if (isPolygon) {
      final v = vertices;
      if (v.isNotEmpty) {
        m['relevancy'] = [
          v.map((p) => p.x).reduce((a, b) => a + b) / v.length,
          v.map((p) => p.y).reduce((a, b) => a + b) / v.length,
        ];
      }
    }
    return m;
  }

  static final _rnd = math.Random.secure();

  /// Random UUID v4, same format the web app uses.
  static String newId() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Colour presets, same as the Vacuula web app.
const boundaryColors = [
  '#ff7a45', '#f5b942', '#b4e04a', '#3ddc97', '#38d0e0',
  '#5aa9ff', '#a78bfa', '#e879f9', '#fb7185', '#f97373',
];

String pickUnusedColor(Iterable<String> used) {
  final u = used.map((c) => c.toLowerCase()).toSet();
  return boundaryColors.firstWhere((c) => !u.contains(c), orElse: () => boundaryColors[u.length % boundaryColors.length]);
}

/// Path segment like the web app sends it: the Vacuula server does not URL-decode
/// paths, so ':' in map ids (timestamps) must stay as is.
String _seg(String s) => Uri.encodeComponent(s).replaceAll('%3A', ':');

/// Map API calls, same endpoints and commands as the Vacuula web app.
extension MapApi on VacuulaApi {
  Future<List<RobotMap>> maps(RobotInfo r) async {
    final data = await getJson('/robot/${_seg(r.serial)}/maps');
    return [for (final m in (data is List ? data : const [])) if (m is Map) RobotMap(m.cast<String, dynamic>())];
  }

  Future<MapGrid> mapGrid(RobotInfo r, String mapId) async {
    final data = await getJson('/robot/${_seg(r.serial)}/maps/${_seg(mapId)}');
    return MapGrid.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Rename / enable a map (Gen3 uses "enabled"; Gen4 ignores it).
  Future<void> updateMap(RobotInfo r, RobotMap map, {required String name, bool? enabled}) =>
      postJson('/robot/${_seg(r.serial)}/maps/${_seg(map.id)}',
          {'name': name, 'enabled': enabled ?? map.enabled ?? true});

  Future<List<Boundary>> boundaries(RobotInfo r, String mapId) async {
    if (r.gen == RobotGen.gen4) {
      final data = await getJson(
          '/robot/${_seg(r.serial)}/maps/${_seg(mapId)}/boundaries');
      return [for (final b in (data is List ? data : const [])) if (b is Map) Boundary(b.cast<String, dynamic>())];
    }
    // Gen3: the boundaries live on the robot
    final res = await command(r.serial, {'cmd': 'getMapBoundaries', 'params': {'mapId': mapId}});
    final list = (res is Map && res['data'] is Map) ? (res['data'] as Map)['boundaries'] : null;
    return [for (final b in (list is List ? list : const [])) if (b is Map) Boundary(b.cast<String, dynamic>())];
  }

  /// Saves the complete list of boundaries for a map.
  Future<void> saveBoundaries(RobotInfo r, RobotMap map, List<Boundary> list) async {
    if (r.gen == RobotGen.gen4) {
      final base = '/robot/${_seg(r.serial)}/maps/${_seg(map.id)}';
      await postJson('$base/boundaries', [for (final b in list) b.raw]);
      // A promoted floorplan must be promoted again for the robot to pick up the change
      if (map.promoted == true) await postJson('$base/promote', null);
      return;
    }
    final res = await command(r.serial, {
      'cmd': 'setMapBoundaries',
      'params': {'mapId': map.id, 'boundaries': [for (final b in list) b.toGen3Json()]},
    });
    if (res is Map && res['result'] != null && res['result'] != 'ok') {
      throw ApiException('The robot did not accept the change (${res['result']})');
    }
  }

  /// Cleans one zone.
  Future<void> cleanZone(RobotInfo r, RobotMap map, Boundary zone, CleaningPrefs p) async {
    if (r.gen == RobotGen.gen4) {
      await command(r.serial, {
        'ability': 'cleaning.start',
        'runs': [
          {
            'map': {'rank_id': map.id, 'track_id': zone.id, 'nogo_enabled': true},
            'settings': {'mode': p.gen4Mode, 'navigation_mode': 'normal'},
          }
        ],
      });
      return;
    }
    await command(r.serial, {
      'cmd': 'startCleaning',
      'params': {'category': 4, 'mode': p.gen3Mode, 'navigationMode': 1, 'mapId': map.id, 'boundaryId': zone.id},
    });
  }

  /// Gen3: start exploring to create a new map (robot must be on the base).
  Future<void> exploreNewMap(RobotInfo r, CleaningPrefs p) => r.gen == RobotGen.gen4
      ? command(r.serial, {
          'ability': 'cleaning.start',
          'runs': [
            {'map': null, 'settings': {'mode': 'eco', 'navigation_mode': 'gentle'}}
          ],
        })
      : command(r.serial, {'cmd': 'startPersistentMapExploration'});
}
