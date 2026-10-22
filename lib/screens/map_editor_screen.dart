import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api.dart';
import '../map/map_models.dart';
import '../map/map_painter.dart';
import '../settings.dart';

/// Shows one map and lets you add, change, switch off and delete
/// no-go lines and zones - the same things as the Vacuula web app.
class MapEditorScreen extends StatefulWidget {
  const MapEditorScreen({
    super.key,
    required this.api,
    required this.robot,
    required this.map,
    required this.settings,
  });

  final VacuulaApi api;
  final RobotInfo robot;
  final RobotMap map;
  final AppSettings settings;

  @override
  State<MapEditorScreen> createState() => _MapEditorScreenState();
}

class _MapEditorScreenState extends State<MapEditorScreen> {
  final _view = TransformationController();
  late RobotMap _map = widget.map;

  MapGrid? _grid;
  ui.Image? _image;
  String? _mapError;

  List<Boundary> _boundaries = const [];
  bool _boundariesLoading = true;
  String? _boundaryError;
  bool _saving = false;
  String? _selectedId;

  // Drawing state
  bool _drawing = false;
  Boundary? _editing; // existing boundary being changed, null = new
  List<MapPoint> _draft = const [];
  bool _draftClosed = false;

  bool _fitted = false;
  Size? _viewport;

  bool get _gen4 => widget.robot.gen == RobotGen.gen4;

  @override
  void initState() {
    super.initState();
    _loadMap();
    _loadBoundaries();
  }

  @override
  void dispose() {
    _view.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _loadMap() async {
    try {
      final g = await widget.api.mapGrid(widget.robot, _map.id);
      final img = await renderGrid(g);
      if (!mounted) return;
      setState(() {
        _grid = g;
        _image = img;
        _mapError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    } catch (e) {
      if (mounted) setState(() => _mapError = '$e');
    }
  }

  Future<void> _loadBoundaries() async {
    setState(() => _boundariesLoading = true);
    try {
      final list = await widget.api.boundaries(widget.robot, _map.id);
      if (mounted) {
        setState(() {
          _boundaries = list;
          _boundaryError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _boundaryError = widget.robot.gen == RobotGen.gen3
            ? 'No-go lines and zones are stored on the robot, so it must be connected. ($e)'
            : '$e');
      }
    } finally {
      if (mounted) setState(() => _boundariesLoading = false);
    }
  }

  /// Zoom so the explored part of the map fills the view.
  void _fit() {
    final g = _grid, vp = _viewport;
    if (g == null || vp == null || _fitted) return;
    final b = g.contentBounds();
    if (b == null) return;
    final w = (b.maxX - b.minX + 1) * cellPx, h = (b.maxY - b.minY + 1) * cellPx;
    final s = math.min(vp.width * 0.9 / w, vp.height * 0.9 / h).clamp(0.05, 40.0);
    final cx = (b.minX * cellPx) + w / 2, cy = (b.minY * cellPx) + h / 2;
    _view.value = Matrix4.identity()
      ..translateByDouble(vp.width / 2 - cx * s, vp.height / 2 - cy * s, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
    _fitted = true;
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  /// Saves the whole list (that is how the robot/server want it), then reloads.
  Future<bool> _save(List<Boundary> list, {String? done}) async {
    setState(() => _saving = true);
    try {
      await widget.api.saveBoundaries(widget.robot, _map, list);
      if (!mounted) return true;
      setState(() => _boundaries = list);
      if (done != null) _toast(done);
      await _loadBoundaries();
      return true;
    } catch (e) {
      if (mounted) _toast('Could not save: $e', error: true);
      await _loadBoundaries();
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------ actions

  void _startDraw([Boundary? existing]) {
    setState(() {
      _drawing = true;
      _editing = existing;
      _draft = existing?.shapePoints ?? const [];
      _draftClosed = existing?.isArea ?? false;
      _selectedId = null;
    });
  }

  void _cancelDraw() => setState(() {
        _drawing = false;
        _editing = null;
        _draft = const [];
        _draftClosed = false;
      });

  void _tapMap(Offset local, Size size) {
    final p = (x: (local.dx / size.width).clamp(0.0, 1.0), y: (local.dy / size.height).clamp(0.0, 1.0));
    if (_drawing) {
      if (_draftClosed) return;
      // Tapping the first point again closes the shape into a zone
      if (_draft.length >= 3) {
        final f = _draft.first;
        final d = (Offset(f.x * size.width, f.y * size.height) - local).distance;
        if (d * _view.value.getMaxScaleOnAxis() < 24) {
          setState(() => _draftClosed = true);
          return;
        }
      }
      setState(() => _draft = [..._draft, p]);
      return;
    }
    // Not drawing: select the boundary under the finger
    Boundary? hit;
    for (final b in _boundaries.reversed) {
      if (_hits(b, p, size)) {
        hit = b;
        break;
      }
    }
    setState(() => _selectedId = hit?.id);
  }

  bool _hits(Boundary b, MapPoint p, Size size) {
    final v = b.shapePoints.map((q) => Offset(q.x * size.width, q.y * size.height)).toList();
    final t = Offset(p.x * size.width, p.y * size.height);
    if (b.isArea && v.length >= 3 && (Path()..addPolygon(v, true)).contains(t)) return true;
    if (b.isArea && v.length >= 2) v.add(v.first); // also hit the closing edge
    final tol = 20 / _view.value.getMaxScaleOnAxis();
    for (var i = 0; i + 1 < v.length; i++) {
      if (_distToSegment(t, v[i], v[i + 1]) < tol) return true;
    }
    return false;
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  Future<void> _finishDraw() async {
    final existing = _editing;
    final details = await _detailsSheet(
      name: existing?.name ?? '',
      color: existing?.color ?? pickUnusedColor(_boundaries.map((b) => b.color)),
      polygon: _draftClosed,
      function: existing == null
          ? 'cleaning'
          : (existing.kind == BoundaryKind.noGoArea || existing.kind == BoundaryKind.noGoZone ? 'nogo' : 'cleaning'),
    );
    if (details == null) return;
    // Gen4: zones are polygons with a function (cleaning / nogo).
    // Gen3: a cleaning zone is a polygon; a no-go area is a no-go line closed on itself.
    final noGo = _draftClosed && details.function == 'nogo';
    final polygon = _draftClosed && (_gen4 || !noGo);
    final vertices = (_draftClosed && !polygon) ? Boundary.closeLoop(_draft) : _draft;
    final fn = _gen4 ? (_draftClosed ? details.function : 'nogo') : null;
    final b = existing == null
        ? Boundary.create(
            name: details.name,
            color: details.color,
            vertices: vertices,
            polygon: polygon,
            function: fn,
          )
        : existing.copyWith(
            name: details.name,
            color: details.color,
            vertices: vertices,
            polygon: polygon,
            function: fn,
          );
    final list = [
      for (final x in _boundaries) x.id == b.id ? b : x,
      if (!_boundaries.any((x) => x.id == b.id)) b,
    ];
    final ok = await _save(list, done: existing == null ? '"${b.name}" added' : '"${b.name}" saved');
    if (ok && mounted) {
      _cancelDraw();
      setState(() => _selectedId = b.id);
    }
  }

  Future<void> _toggle(Boundary b, bool on) =>
      _save([for (final x in _boundaries) x.id == b.id ? x.copyWith(enabled: on) : x]);

  Future<void> _delete(Boundary b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${b.name.isEmpty ? b.kindLabel : b.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _selectedId = null);
    await _save([for (final x in _boundaries) if (x.id != b.id) x], done: 'Deleted');
  }

  Future<void> _clean(Boundary zone) async {
    try {
      await widget.api.cleanZone(widget.robot, _map, zone, widget.settings.cleaning);
      _toast('Cleaning "${zone.name}"');
    } catch (e) {
      _toast('Could not start: $e', error: true);
    }
  }

  Future<void> _editMap() async {
    final name = TextEditingController(text: _map.rawName == '(unnamed)' ? '' : _map.rawName);
    var enabled = _map.enabled ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Map details'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            if (_map.enabled != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                subtitle: const Text('The robot uses this map'),
                value: enabled,
                onChanged: (v) => setD(() => enabled = v),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await widget.api.updateMap(widget.robot, _map, name: name.text.trim(), enabled: enabled);
      final maps = await widget.api.maps(widget.robot);
      final m = maps.where((x) => x.id == _map.id);
      if (mounted && m.isNotEmpty) setState(() => _map = m.first);
    } catch (e) {
      _toast('Could not save: $e', error: true);
    }
  }

  Future<({String name, String color, String function})?> _detailsSheet({
    required String name,
    required String color,
    required bool polygon,
    required String function,
  }) {
    final nameCtl = TextEditingController(text: name);
    var col = color;
    var fn = function == 'nogo' ? 'nogo' : 'cleaning';
    return showModalBottomSheet<({String name, String color, String function})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  !polygon
                      ? 'No-go line'
                      : fn == 'nogo'
                          ? (_gen4 ? 'No-go zone' : 'No-go area')
                          : 'Cleaning zone',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                !polygon
                    ? 'The robot will not cross this line.'
                    : fn == 'nogo'
                        ? (_gen4
                            ? 'The robot stays out of this area.'
                            : 'The robot stays out of this area. Saved as a no-go line around it, '
                                'since D3-D7 robots have no-go lines but not no-go zones.')
                        : 'An area you can clean on its own.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtl,
                autofocus: name.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              ),
              if (polygon) ...[
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: [
                    const ButtonSegment(value: 'cleaning', label: Text('Cleaning zone')),
                    ButtonSegment(value: 'nogo', label: Text(_gen4 ? 'No-go zone' : 'No-go area')),
                  ],
                  selected: {fn},
                  onSelectionChanged: (s) => setS(() => fn = s.first),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final c in boundaryColors)
                  GestureDetector(
                    onTap: () => setS(() => col = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: parseHex(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == col ? Theme.of(ctx).colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final n = nameCtl.text.trim();
                  Navigator.pop(ctx, (
                    name: n.isEmpty
                        ? (!polygon ? 'No-go line' : (fn == 'nogo' ? 'No-go area' : 'Zone'))
                        : n,
                    color: col,
                    function: fn,
                  ));
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_drawing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _drawing) _cancelDraw();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_drawing ? (_editing == null ? 'Draw' : 'Change shape') : _map.name),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (!_drawing)
              IconButton(tooltip: 'Map details', icon: const Icon(Icons.edit_outlined), onPressed: _editMap),
          ],
        ),
        body: Column(children: [
          Expanded(child: _mapView(cs)),
          if (_drawing) _drawBar(cs) else _panel(cs),
        ]),
      ),
    );
  }

  Widget _mapView(ColorScheme cs) {
    if (_mapError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load the map: $_mapError', textAlign: TextAlign.center),
        ),
      );
    }
    final g = _grid, img = _image;
    if (g == null || img == null) return const Center(child: CircularProgressIndicator());
    final size = Size(g.width * cellPx, g.height * cellPx);
    return LayoutBuilder(builder: (ctx, c) {
      _viewport = Size(c.maxWidth, c.maxHeight);
      if (!_fitted) WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
      return Stack(children: [
        Container(color: mapBackground),
        InteractiveViewer(
          transformationController: _view,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          minScale: 0.05,
          maxScale: 40,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tapMap(d.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: MapPainter(
                image: img,
                grid: g,
                boundaries: _boundaries,
                view: _view,
                base: _map.base ?? g.base,
                selectedId: _selectedId,
                hiddenId: _drawing ? _editing?.id : null,
                draft: _drawing ? _draft : const [],
                draftClosed: _draftClosed,
                draftColor: _editing != null ? parseHex(_editing!.color) : mapDraft,
              ),
            ),
          ),
        ),
        if (_drawing)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              color: cs.surface.withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _draftClosed
                      ? 'Zone closed. Tap Done to name it and save.'
                      : _draft.length < 2
                          ? 'Tap the map to add points. Pinch to zoom, drag to move the map.'
                          : 'Keep tapping to add points. Tap Done for a no-go line, or tap the first point (or Close) to make a zone or no-go area.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'fit',
            tooltip: 'Fit map',
            onPressed: () {
              _fitted = false;
              _fit();
            },
            child: const Icon(Icons.fit_screen_rounded),
          ),
        ),
      ]);
    });
  }

  Widget _drawBar(ColorScheme cs) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          IconButton.outlined(
            tooltip: 'Cancel',
            onPressed: _cancelDraw,
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Undo',
            onPressed: _draft.isEmpty && !_draftClosed
                ? null
                : () => setState(() {
                      if (_draftClosed) {
                        _draftClosed = false;
                      } else {
                        _draft = _draft.sublist(0, _draft.length - 1);
                      }
                    }),
            icon: const Icon(Icons.undo_rounded),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _draft.length >= 3 && !_draftClosed ? () => setState(() => _draftClosed = true) : null,
            icon: const Icon(Icons.pentagon_outlined),
            label: const Text('Close'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _draft.length >= 2 && !_saving ? _finishDraw : null,
            child: const Text('Done'),
          ),
        ]),
      ),
    );
  }

  Widget _panel(ColorScheme cs) {
    final t = Theme.of(context).textTheme;
    final selected = _boundaries.where((b) => b.id == _selectedId).toList();
    return Material(
      elevation: 3,
      color: cs.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.38),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    selected.isNotEmpty ? 'Selected' : 'No-go lines and zones',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _boundaryError == null && !_boundariesLoading ? () => _startDraw() : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add'),
                ),
              ]),
              const SizedBox(height: 6),
              if (_boundariesLoading && _boundaries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_boundaryError != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_off_rounded, color: cs.error),
                  title: Text(_boundaryError!, style: t.bodySmall),
                  trailing: TextButton(onPressed: _loadBoundaries, child: const Text('Retry')),
                )
              else if (_boundaries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'None yet. Tap Add and draw on the map: a line the robot will not cross, '
                    'or a closed shape to make a zone you can clean on its own.',
                    style: t.bodySmall,
                  ),
                )
              else
                for (final b in (selected.isNotEmpty ? selected : _boundaries)) _boundaryTile(b, cs, expanded: selected.isNotEmpty),
              if (selected.isNotEmpty)
                TextButton(onPressed: () => setState(() => _selectedId = null), child: const Text('Show all')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boundaryTile(Boundary b, ColorScheme cs, {bool expanded = false}) {
    final color = parseHex(b.color);
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: color.withValues(alpha: 0.12),
      leading: Icon(b.isArea ? Icons.pentagon_outlined : Icons.horizontal_rule_rounded, color: color),
      title: Text(b.name.isEmpty ? b.kindLabel : b.name),
      subtitle: Text(b.kindLabel + (b.canToggle && !b.enabled ? ' · off' : ''), style: TextStyle(color: color)),
      trailing: b.canToggle
          ? Switch(value: b.enabled, onChanged: _saving ? null : (v) => _toggle(b, v))
          : FilledButton.tonal(
              onPressed: widget.robot.connected ? () => _clean(b) : null,
              child: const Text('Clean'),
            ),
      onTap: () => setState(() => _selectedId = expanded ? null : b.id),
    );
    if (!expanded) return Padding(padding: const EdgeInsets.only(bottom: 6), child: tile);
    return Column(children: [
      tile,
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _startDraw(b),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            onPressed: _saving ? null : () => _delete(b),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete'),
          ),
        ),
      ]),
    ]);
  }
}
