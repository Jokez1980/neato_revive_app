import 'package:flutter/material.dart';

import '../api.dart';
import '../map/map_models.dart';
import '../schedule/schedule_models.dart';

/// Cleaning schedule of one robot - same features as the Vacuula web app.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.api, required this.robot});

  final VacuulaApi api;
  final RobotInfo robot;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

/// A zone that can be picked in a schedule.
class _ZoneOption {
  _ZoneOption(this.id, this.label, this.mapId);
  final String id;
  final String label;
  final String mapId;
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool get _gen4 => widget.robot.gen == RobotGen.gen4;

  Gen3Schedule? _g3;
  Gen4Schedule? _g4;
  String? _error;
  bool _busy = false;

  List<_ZoneOption> _zones = const [];
  RobotMap? _promoted; // Gen4: floorplan in use

  /// Phone's offset from UTC (Gen3 robots store schedule times in UTC).
  int get _offset => DateTime.now().timeZoneOffset.inMinutes;

  String get _offsetLabel {
    final o = _offset;
    if (o == 0) return 'UTC';
    final a = o.abs();
    return 'UTC${o < 0 ? '-' : '+'}${a ~/ 60}${a % 60 == 0 ? '' : ':${(a % 60).toString().padLeft(2, '0')}'}';
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadZones();
  }

  Future<void> _load() async {
    try {
      if (_gen4) {
        final s = await widget.api.gen4Schedule(widget.robot);
        if (mounted) setState(() => _g4 = s);
      } else {
        final s = await widget.api.gen3Schedule(widget.robot);
        if (mounted) setState(() => _g3 = s);
      }
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadZones() async {
    try {
      final maps = await widget.api.maps(widget.robot);
      final zones = <_ZoneOption>[];
      if (_gen4) {
        final p = maps.where((m) => m.promoted == true);
        _promoted = p.isEmpty ? null : p.first;
        if (_promoted != null) {
          for (final b in await widget.api.boundaries(widget.robot, _promoted!.id)) {
            if (b.canClean) zones.add(_ZoneOption(b.id, b.name.isEmpty ? 'Zone' : b.name, _promoted!.id));
          }
        }
      } else {
        for (final m in maps.where((m) => m.enabled != false)) {
          for (final b in await widget.api.boundaries(widget.robot, m.id)) {
            if (b.canClean) zones.add(_ZoneOption(b.id, '${m.name} - ${b.name.isEmpty ? 'Zone' : b.name}', m.id));
          }
        }
      }
      if (mounted) setState(() => _zones = zones);
    } catch (_) {
      // Zones are optional; the schedule works without them
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) _toast(done);
    } catch (e) {
      _toast('Could not save: $e', error: true);
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _zoneName(String? id, [String? fallback]) {
    if (id == null) return 'Whole home';
    for (final z in _zones) {
      if (z.id == id) return z.label;
    }
    return fallback ?? 'Zone';
  }

  // ------------------------------------------------------------ Gen3

  Future<void> _editGen3([int? index]) async {
    final s = _g3;
    if (s == null) return;
    final existing = index == null ? null : s.events[index];
    final local = existing?.local(_offset);
    final result = await showModalBottomSheet<_EventForm>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EventSheet(
        title: existing == null ? 'New cleaning' : 'Change cleaning',
        initial: _EventForm(
          days: {local?.day ?? (DateTime.now().weekday - 1)},
          time: local?.time ?? '09:00',
          mode: existing?.mode == 1 ? 'eco' : 'normal',
          zoneIds: {if (existing?.boundaryId != null) existing!.boundaryId!},
        ),
        modes: const {'normal': 'Normal', 'eco': 'Eco'},
        zones: _zones,
        multiZone: false,
        timeHint: 'Times are in your phone\'s time zone ($_offsetLabel).',
        onDelete: existing == null ? null : () => Navigator.pop(context, _EventForm.deleted),
      ),
    );
    if (result == null) return;
    final others = [for (var i = 0; i < s.events.length; i++) if (i != index) s.events[i]];
    if (identical(result, _EventForm.deleted)) {
      await _run(() => widget.api.setGen3Events(widget.robot, others), done: 'Deleted');
      return;
    }
    final added = [
      for (final d in result.days)
        Gen3Event.fromLocal(
          day: d,
          time: result.time,
          mode: result.mode == 'eco' ? 1 : 2,
          offsetMinutes: _offset,
          boundaryId: result.zoneIds.isEmpty ? null : result.zoneIds.first,
        ),
    ];
    await _run(
      () async {
        await widget.api.setGen3Events(widget.robot, [...others, ...added]);
        if (!s.enabled) await widget.api.setGen3ScheduleEnabled(widget.robot, true);
      },
      done: existing == null ? 'Added' : 'Saved',
    );
  }

  Widget _gen3Body(Gen3Schedule s) {
    final t = Theme.of(context).textTheme;
    final items = [
      for (var i = 0; i < s.events.length; i++) (i: i, e: s.events[i], l: s.events[i].local(_offset)),
    ]..sort((a, b) => a.l.day != b.l.day ? a.l.day.compareTo(b.l.day) : a.l.time.compareTo(b.l.time));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: SwitchListTile(
            title: const Text('Schedule'),
            subtitle: Text(s.enabled ? 'On - the robot cleans at these times' : 'Off - nothing runs automatically'),
            value: s.enabled,
            onChanged: _busy
                ? null
                : (v) => _run(() => widget.api.setGen3ScheduleEnabled(widget.robot, v),
                    done: v ? 'Schedule on' : 'Schedule off'),
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No scheduled cleanings yet. Tap + to add one.', textAlign: TextAlign.center, style: t.bodyLarge),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final it in items)
                ListTile(
                  leading: CircleAvatar(child: Text(weekdayShort[it.l.day].substring(0, 2))),
                  title: Text('${weekdayNames[it.l.day]}  ${it.l.time}'),
                  subtitle: Text(
                      '${it.e.mode == 1 ? 'Eco' : 'Normal'} · ${_zoneName(it.e.boundaryId, it.e.boundaryName)}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy ? null : () => _editGen3(it.i),
                ),
            ]),
          ),
        const SizedBox(height: 12),
        Text(
          'Times are shown in your phone\'s time zone ($_offsetLabel). The robot keeps them in UTC, '
          'so after a daylight saving change they run an hour earlier or later - just edit them again.',
          style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Gen4

  Future<void> _editGen4([Gen4Event? existing]) async {
    final result = await showModalBottomSheet<_EventForm>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EventSheet(
        title: existing == null ? 'New cleaning' : 'Change cleaning',
        initial: _EventForm(
          days: existing?.days.toSet() ?? {DateTime.now().weekday - 1},
          time: existing?.time ?? '09:00',
          mode: existing?.mode ?? 'auto',
          navigation: existing?.navigation ?? 'normal',
          zoneIds: existing?.zoneIds.toSet() ?? {},
          useMap: existing == null ? _promoted != null : existing.mapId != null,
        ),
        modes: const {'auto': 'Auto', 'eco': 'Eco', 'turbo': 'Turbo', 'max': 'Max'},
        navigations: const {'normal': 'Normal', 'gentle': 'Gentle'},
        zones: _zones,
        multiZone: true,
        mapName: _promoted?.name,
        onDelete: existing?.id == null ? null : () => Navigator.pop(context, _EventForm.deleted),
      ),
    );
    if (result == null) return;
    if (identical(result, _EventForm.deleted)) {
      await _run(() => widget.api.deleteGen4Event(widget.robot, existing!.id!), done: 'Deleted');
      return;
    }
    final e = Gen4Event.build(
      id: existing?.id,
      enabled: existing?.enabled ?? true,
      days: result.days.toList(),
      time: result.time,
      mode: result.mode,
      navigation: result.navigation,
      mapId: result.useMap ? _promoted?.id : null,
      zoneIds: result.useMap ? result.zoneIds.toList() : const [],
    );
    await _run(() => widget.api.saveGen4Event(widget.robot, e), done: existing == null ? 'Added' : 'Saved');
  }

  Widget _gen4Body(Gen4Schedule s) {
    final t = Theme.of(context).textTheme;
    final events = [...s.events]..sort((a, b) => a.time.compareTo(b.time));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No scheduled cleanings yet. Tap + to add one.', textAlign: TextAlign.center, style: t.bodyLarge),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final e in events)
                ListTile(
                  title: Text('${e.time}  ·  ${daysLabel(e.days)}'),
                  subtitle: Text([
                    e.mode[0].toUpperCase() + e.mode.substring(1),
                    if (e.mapId == null)
                      'Whole home'
                    else if (e.zoneIds.isEmpty)
                      'Whole floorplan'
                    else
                      e.zoneIds.map((z) => _zoneName(z)).join(', '),
                  ].join(' · ')),
                  trailing: Switch(
                    value: e.enabled,
                    onChanged: _busy
                        ? null
                        : (v) => _run(() => widget.api.saveGen4Event(widget.robot, Gen4Event({...e.raw, 'enabled': v}))),
                  ),
                  onTap: _busy ? null : () => _editGen4(e),
                ),
            ]),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = _gen4 ? _g4 != null : _g3 != null;
    return Scaffold(
      appBar: AppBar(
        title: Text('Schedule · ${widget.robot.name}'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      floatingActionButton: ready && _error == null
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _gen4 ? _editGen4() : _editGen3(),
              icon: const Icon(Icons.add_alarm_rounded),
              label: const Text('Add'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _loadZones();
        },
        child: _error != null
            ? ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  child: ListTile(
                    leading: Icon(Icons.link_off_rounded, color: cs.error),
                    title: const Text('Could not read the schedule'),
                    subtitle: Text('The schedule is stored on the robot, so it must be connected.\n$_error'),
                    trailing: TextButton(onPressed: _load, child: const Text('Retry')),
                  ),
                ),
              ])
            : !ready
                ? const Center(child: CircularProgressIndicator())
                : (_gen4 ? _gen4Body(_g4!) : _gen3Body(_g3!)),
      ),
    );
  }
}

// ------------------------------------------------------------ add / edit sheet

class _EventForm {
  _EventForm({
    required this.days,
    required this.time,
    required this.mode,
    this.navigation = 'normal',
    this.zoneIds = const {},
    this.useMap = false,
  });

  /// Returned by the sheet when the user taps Delete.
  static final deleted = _EventForm(days: {}, time: '', mode: '');

  final Set<int> days; // Monday = 0
  final String time;
  final String mode;
  final String navigation;
  final Set<String> zoneIds;
  final bool useMap;
}

class _EventSheet extends StatefulWidget {
  const _EventSheet({
    required this.title,
    required this.initial,
    required this.modes,
    required this.zones,
    required this.multiZone,
    this.navigations,
    this.mapName,
    this.timeHint,
    this.onDelete,
  });

  final String title;
  final _EventForm initial;
  final Map<String, String> modes;
  final Map<String, String>? navigations; // Gen4 only
  final List<_ZoneOption> zones;
  final bool multiZone; // Gen4: several zones; Gen3: one
  final String? mapName; // Gen4: floorplan in use
  final String? timeHint;
  final VoidCallback? onDelete;

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  late Set<int> _days = {...widget.initial.days};
  late String _time = widget.initial.time;
  late String _mode = widget.modes.containsKey(widget.initial.mode) ? widget.initial.mode : widget.modes.keys.first;
  late String _nav = widget.initial.navigation;
  late Set<String> _zones = {...widget.initial.zoneIds};
  late bool _useMap = widget.initial.useMap;

  Future<void> _pickTime() async {
    final m = parseHHMM(_time) ?? 540;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      builder: (ctx, child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked != null) setState(() => _time = formatHHMM(picked.hour * 60 + picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final gen4 = widget.navigations != null;
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(s, style: t.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
        );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: t.titleLarge),
              label('Days'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var d = 0; d < 7; d++)
                  FilterChip(
                    label: Text(weekdayShort[d]),
                    selected: _days.contains(d),
                    onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
                  ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                ActionChip(label: const Text('Every day'), onPressed: () => setState(() => _days = {0, 1, 2, 3, 4, 5, 6})),
                ActionChip(label: const Text('Weekdays'), onPressed: () => setState(() => _days = {0, 1, 2, 3, 4})),
                ActionChip(label: const Text('Weekends'), onPressed: () => setState(() => _days = {5, 6})),
              ]),
              label('Time'),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded),
                label: Text(_time, style: t.titleLarge),
              ),
              if (widget.timeHint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(widget.timeHint!, style: t.bodySmall),
                ),
              label('Cleaning mode'),
              SegmentedButton<String>(
                segments: [for (final e in widget.modes.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              if (gen4) ...[
                label('Navigation'),
                SegmentedButton<String>(
                  segments: [
                    for (final e in widget.navigations!.entries) ButtonSegment(value: e.key, label: Text(e.value))
                  ],
                  selected: {_nav},
                  onSelectionChanged: (s) => setState(() => _nav = s.first),
                ),
              ],
              label('Where'),
              if (gen4) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.mapName == null ? 'Use floorplan' : 'Use floorplan "${widget.mapName}"'),
                  subtitle: Text(widget.mapName == null
                      ? 'No floorplan in use - the robot cleans everywhere it can reach.'
                      : 'Respects no-go lines and zones, and lets you pick zones.'),
                  value: _useMap && widget.mapName != null,
                  onChanged: widget.mapName == null ? null : (v) => setState(() => _useMap = v),
                ),
                if (_useMap && widget.mapName != null)
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final z in widget.zones)
                      FilterChip(
                        label: Text(z.label),
                        selected: _zones.contains(z.id),
                        onSelected: (v) => setState(() => v ? _zones.add(z.id) : _zones.remove(z.id)),
                      ),
                    if (widget.zones.isEmpty) Text('No cleaning zones on this floorplan.', style: t.bodySmall),
                  ]),
              ] else
                DropdownButtonFormField<String>(
                  initialValue: _zones.isEmpty
                      ? ''
                      : (widget.zones.any((z) => z.id == _zones.first) ? _zones.first : ''),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Whole home')),
                    for (final z in widget.zones) DropdownMenuItem(value: z.id, child: Text(z.label)),
                  ],
                  onChanged: (v) => setState(() => _zones = (v == null || v.isEmpty) ? {} : {v}),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _days.isEmpty
                    ? null
                    : () => Navigator.pop(
                          context,
                          _EventForm(
                            days: _days,
                            time: _time,
                            mode: _mode,
                            navigation: _nav,
                            zoneIds: _zones,
                            useMap: _useMap && widget.mapName != null,
                          ),
                        ),
                child: Text(_days.isEmpty ? 'Pick at least one day' : 'Save'),
              ),
              if (widget.onDelete != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
