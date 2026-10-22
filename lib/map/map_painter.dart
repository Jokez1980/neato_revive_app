import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'map_models.dart';

/// Map colours, same as the Vacuula web app's dark map theme.
const mapBackground = Color(0xFF0F1113);
const mapFloor = Color(0xFF2F353B);
const mapWall = Color(0xFF3DDC97);
const mapDraft = Color(0xFF4AB3F5);

/// Size of one map cell in the editor's own coordinate space (before zoom).
const cellPx = 4.0;

Color parseHex(String hex, [Color fallback = const Color(0xFFFF7A45)]) {
  var s = hex.trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  final v = int.tryParse(s, radix: 16);
  return (s.length == 6 && v != null) ? Color(0xFF000000 | v) : fallback;
}

/// Turns the occupancy grid into an image (one pixel per cell).
Future<ui.Image> renderGrid(MapGrid g) {
  final px = Uint8List(g.width * g.height * 4);
  for (var i = 0; i < g.cells.length; i++) {
    final v = g.cells[i];
    if (v == 0) continue; // unexplored: transparent
    final c = v == 1 ? mapFloor : mapWall;
    final o = i * 4;
    px[o] = (c.r * 255).round();
    px[o + 1] = (c.g * 255).round();
    px[o + 2] = (c.b * 255).round();
    px[o + 3] = 255;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, g.width, g.height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

class MapPainter extends CustomPainter {
  MapPainter({
    required this.image,
    required this.grid,
    required this.boundaries,
    required this.view,
    this.base,
    this.selectedId,
    this.hiddenId,
    this.draft = const [],
    this.draftClosed = false,
    this.draftColor = mapDraft,
  }) : super(repaint: view);

  final ui.Image image;
  final MapGrid grid;
  final List<Boundary> boundaries;
  final TransformationController view;
  final MapPoint? base;
  final String? selectedId;
  final String? hiddenId; // boundary being edited (drawn as draft instead)
  final List<MapPoint> draft;
  final bool draftClosed;
  final Color draftColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Keep lines and dots the same size on screen whatever the zoom
    final zoom = view.value.getMaxScaleOnAxis();
    double px(double screenPixels) => screenPixels / zoom;
    Offset at(MapPoint p) => Offset(p.x * size.width, p.y * size.height);

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, grid.width.toDouble(), grid.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );

    for (final b in boundaries) {
      if (b.id == hiddenId) continue;
      final pts = b.vertices.map(at).toList();
      if (pts.length < 2) continue;
      final color = parseHex(b.color);
      final alpha = b.enabled ? 1.0 : 0.4;
      final selected = b.id == selectedId;
      final path = Path()..addPolygon(pts, b.isPolygon);
      if (b.isPolygon) {
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: (selected ? 0.38 : 0.22) * alpha));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = px(selected ? 4 : 2.5)
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      if (b.name.isNotEmpty) {
        final c = b.isPolygon
            ? Offset(pts.map((p) => p.dx).reduce((a, b) => a + b) / pts.length,
                pts.map((p) => p.dy).reduce((a, b) => a + b) / pts.length)
            : Offset((pts.first.dx + pts.last.dx) / 2, (pts.first.dy + pts.last.dy) / 2);
        _label(canvas, b.name, c, color, zoom);
      }
    }

    if (base != null) {
      final c = at(base!);
      canvas.drawCircle(c, px(9), Paint()..color = Colors.white);
      canvas.drawCircle(c, px(6), Paint()..color = const Color(0xFF1F9E78));
    }

    if (draft.isNotEmpty) {
      final pts = draft.map(at).toList();
      final path = Path()..addPolygon(pts, draftClosed);
      if (draftClosed) canvas.drawPath(path, Paint()..color = draftColor.withValues(alpha: 0.25));
      canvas.drawPath(
        path,
        Paint()
          ..color = draftColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = px(3)
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      for (var i = 0; i < pts.length; i++) {
        canvas.drawCircle(pts[i], px(i == 0 ? 7 : 5), Paint()..color = Colors.white);
        canvas.drawCircle(pts[i], px(i == 0 ? 5 : 3.5), Paint()..color = draftColor);
      }
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color, double zoom) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Colors.black.withValues(alpha: 0.9), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(1 / zoom);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(MapPainter old) =>
      old.image != image ||
      old.boundaries != boundaries ||
      old.selectedId != selectedId ||
      old.hiddenId != hiddenId ||
      old.draft != draft ||
      old.draftClosed != draftClosed ||
      old.draftColor != draftColor ||
      old.base != base;
}
