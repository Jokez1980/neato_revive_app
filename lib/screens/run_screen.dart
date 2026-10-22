import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api.dart';
import '../map/map_models.dart';
import '../map/map_painter.dart';
import '../problems.dart';
import '../robot/robot_details.dart';

/// Colour of the path the robot drove.
const _pathColor = Color(0xFFFF8A3D);

/// One earlier cleaning: the map with where the robot cleaned, and the details.
class RunScreen extends StatefulWidget {
  const RunScreen({super.key, required this.api, required this.robot, required this.run});

  final VacuulaApi api;
  final RobotInfo robot;
  final CleaningRun run;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  _RunPicture? _picture;
  bool _loading = true;
  String? _mapNote;

  @override
  void initState() {
    super.initState();
    _loadMap();
  }

  Future<void> _loadMap() async {
    try {
      final results = await Future.wait<Object?>([
        widget.api.mapGrid(widget.robot, widget.run.id).then<Object?>((g) => g, onError: (_) => null),
        widget.api.runPathJson(widget.robot, widget.run.id),
      ]);
      final floor = results[0] as MapGrid?;
      final pathJson = results[1] as Map<String, dynamic>?;
      final path = pathJson == null ? null : PathGrid.tryParse(pathJson);
      if (floor == null && path == null) {
        _mapNote = 'No map was saved for this cleaning.';
      } else {
        _picture = await _RunPicture.render(floor, path, gen3: widget.robot.gen == RobotGen.gen3);
        if (_picture == null) _mapNote = 'The map for this cleaning is empty.';
      }
    } catch (e) {
      _mapNote = 'Could not load the map ($e).';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _picture?.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.run;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget row(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(k, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
            Expanded(child: Text(v, style: t.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600))),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(formatDateTime(r.start))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: mapBackground,
            child: _loading
                ? const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))
                : _picture == null
                    ? SizedBox(
                        height: 120,
                        child: Center(
                          child: Text(_mapNote ?? '', style: t.bodyMedium?.copyWith(color: Colors.white70)),
                        ),
                      )
                    : _MapView(picture: _picture!),
          ),
        ),
        if (_picture != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Container(width: 14, height: 14, decoration: BoxDecoration(color: _pathColor, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text('Where it cleaned', style: t.bodySmall),
              const SizedBox(width: 16),
              Container(width: 14, height: 14, decoration: BoxDecoration(color: mapWall, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text('Walls', style: t.bodySmall),
              const Spacer(),
              Text('Pinch to zoom', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        const SizedBox(height: 16),
        row('Result', r.complete ? 'Completed' : _pretty(r.status), color: r.complete ? cs.primary : cs.error),
        if (r.error != null) row('Problem', problemText(r.error!), color: cs.error),
        row('Started', formatDateTime(r.start)),
        row('Ended', formatDateTime(r.end)),
        row('Duration', formatDuration(r.duration)),
        row('Area', formatArea(r.areaM2)),
        if (r.batteryUsed != null) row('Battery used', '${r.batteryUsed} %'),
        if (r.settings != null) row('Settings', r.settings!),
        if (r.startedBy != null) row('Started from', _pretty(r.startedBy!)),
        row('Recharges', '${r.chargeStops}'),
        row('Picked up', '${r.pickups} ${r.pickups == 1 ? 'time' : 'times'}'),
      ]),
    );
  }

  static String _pretty(String s) {
    final v = s.replaceAll('_', ' ');
    return v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);
  }
}

class _MapView extends StatelessWidget {
  const _MapView({required this.picture});
  final _RunPicture picture;

  @override
  Widget build(BuildContext context) {
    final p = picture;
    final ratio = p.image.width / p.image.height;
    return LayoutBuilder(builder: (context, c) {
      final maxH = MediaQuery.of(context).size.height * 0.55;
      var w = c.maxWidth, h = w / ratio;
      if (h > maxH) {
        h = maxH;
        w = h * ratio;
      }
      return SizedBox(
        height: h,
        child: InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: SizedBox(
              width: w,
              height: h,
              child: CustomPaint(painter: _RunPainter(p)),
            ),
          ),
        ),
      );
    });
  }
}

class _RunPainter extends CustomPainter {
  _RunPainter(this.p);
  final _RunPicture p;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      p.image,
      Rect.fromLTWH(0, 0, p.image.width.toDouble(), p.image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
    final b = p.base;
    if (b != null) {
      final c = Offset(b.dx / p.image.width * size.width, b.dy / p.image.height * size.height);
      final r = size.width / p.image.width * 3 + 3;
      canvas.drawCircle(c, r + 2, Paint()..color = Colors.white);
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFF4AB3F5));
    }
  }

  @override
  bool shouldRepaint(_RunPainter old) => old.p != p;
}

/// The floor map with the robot's path on top, cropped to what was explored.
class _RunPicture {
  _RunPicture(this.image, this.base);
  final ui.Image image;

  /// Base position in image pixels.
  final Offset? base;

  static Future<_RunPicture?> render(MapGrid? floor, PathGrid? path, {required bool gen3}) async {
    final w = floor?.width ?? path!.width, h = floor?.height ?? path!.height;
    // Only overlay the path if it is the same grid as the floor map.
    final p = (path != null && path.width == w && path.height == h) ? path.cells : null;
    final pathOnly = floor == null;

    // Values in the path map that are not path: Gen3 uses 128 for "never
    // went here" and 100/200 for the dock marker (Vacuula's map_utils.py).
    // Gen4: like the Vacuula web app, skip the highest value.
    final ignore = <int>{};
    if (gen3) {
      ignore.addAll(const [100, 128, 200]);
    } else if (p != null) {
      final distinct = <int>{for (final v in p) if (v != 0) v}.toList()..sort((a, b) => b.compareTo(a));
      ignore.addAll(distinct.take(1));
    }

    bool used(int i) =>
        (!pathOnly && floor.cells[i] != 0) || (p != null && p[i] != 0 && !ignore.contains(p[i]));

    var minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (used(y * w + x)) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return null;
    const pad = 3;
    minX = (minX - pad).clamp(0, w - 1);
    minY = (minY - pad).clamp(0, h - 1);
    maxX = (maxX + pad).clamp(0, w - 1);
    maxY = (maxY + pad).clamp(0, h - 1);
    final cw = maxX - minX + 1, ch = maxY - minY + 1;

    int ch8(double v) => (v * 255).round();
    final px = Uint8List(cw * ch * 4);
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        final i = (y + minY) * w + (x + minX);
        final o = (y * cw + x) * 4;
        Color? c;
        if (!pathOnly && floor.cells[i] != 0) c = floor.cells[i] == 1 ? mapFloor : mapWall;
        if (p != null && p[i] != 0 && !ignore.contains(p[i])) {
          c = c == null ? _pathColor : Color.lerp(c, _pathColor, 0.75);
        }
        if (c == null) continue;
        px[o] = ch8(c.r);
        px[o + 1] = ch8(c.g);
        px[o + 2] = ch8(c.b);
        px[o + 3] = 255;
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, cw, ch, ui.PixelFormat.rgba8888, done.complete);
    final image = await done.future;

    Offset? base;
    final b = floor?.base;
    if (b != null) {
      // The server gives the base either as 0..1 (normalised) or as cells.
      final bx = b.x <= 1.0 ? b.x * w : b.x;
      final by = b.y <= 1.0 ? b.y * h : b.y;
      base = Offset(bx - minX + 0.5, by - minY + 0.5);
    }
    return _RunPicture(image, base);
  }
}

/// The run's path grid. Raw values are kept as they are (they can be larger
/// than 255), unlike the floor map.
class PathGrid {
  PathGrid(this.width, this.height, this.cells);
  final int width;
  final int height;
  final Int32List cells;

  static PathGrid? tryParse(Map<String, dynamic> j) {
    final w = j['width'], h = j['height'], rle = j['rle'];
    if (w is! num || h is! num || rle is! List) return null;
    final cells = Int32List(w.toInt() * h.toInt());
    var i = 0;
    for (final run in rle) {
      if (run is! List || run.length < 2 || run[0] is! num || run[1] is! num) continue;
      final v = (run[0] as num).toInt();
      final end = (i + (run[1] as num).toInt()).clamp(0, cells.length);
      if (v != 0) cells.fillRange(i, end, v);
      i = end;
      if (i >= cells.length) break;
    }
    return PathGrid(w.toInt(), h.toInt(), cells);
  }
}
