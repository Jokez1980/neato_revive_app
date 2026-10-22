import 'package:flutter/material.dart';

import '../api.dart';
import '../map/map_models.dart';
import '../settings.dart';
import 'map_editor_screen.dart';

/// Lists the saved maps of one robot.
class MapsScreen extends StatefulWidget {
  const MapsScreen({super.key, required this.api, required this.robot, required this.settings});

  final VacuulaApi api;
  final RobotInfo robot;
  final AppSettings settings;

  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen> {
  List<RobotMap>? _maps;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final maps = await widget.api.maps(widget.robot);
      maps.sort((a, b) => (b.created ?? DateTime(0)).compareTo(a.created ?? DateTime(0)));
      if (mounted) {
        setState(() {
          _maps = maps;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _toggle(RobotMap m, bool enabled) async {
    try {
      await widget.api.updateMap(widget.robot, m, name: m.rawName, enabled: enabled);
      await _load();
    } catch (e) {
      _toast('Could not save: $e', error: true);
    }
  }

  Future<void> _explore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a new map?'),
        content: const Text(
          'The robot leaves the base and explores your home to make a map. '
          'Let it finish and return to the base on its own - if it is paused, '
          'picked up or gets stuck, the map is not saved.\n\n'
          'The robot must be on the base to start.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.exploreNewMap(widget.robot, widget.settings.cleaning);
      _toast('Mapping started. The map shows up here a few minutes after the robot is back on the base.');
    } catch (e) {
      _toast('Could not start: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final maps = _maps;
    return Scaffold(
      appBar: AppBar(title: Text('Maps · ${widget.robot.name}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_error != null)
              Card(
                child: ListTile(
                  leading: Icon(Icons.error_outline_rounded, color: cs.error),
                  title: const Text('Could not load maps'),
                  subtitle: Text(_error!),
                  trailing: TextButton(onPressed: _load, child: const Text('Retry')),
                ),
              )
            else if (maps == null)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (maps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text('No maps yet.', textAlign: TextAlign.center, style: t.bodyLarge),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(children: [
                  for (final m in maps)
                    ListTile(
                      leading: const Icon(Icons.map_outlined),
                      title: Text(m.name),
                      subtitle: Text([
                        if (m.created != null) _date(m.created!),
                        if (m.promoted == true) 'In use',
                        if (m.enabled == false) 'Disabled',
                      ].join(' · ')),
                      trailing: m.enabled != null
                          ? Switch(value: m.enabled!, onChanged: (v) => _toggle(m, v))
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => MapEditorScreen(
                            api: widget.api,
                            robot: widget.robot,
                            map: m,
                            settings: widget.settings,
                          ),
                        ));
                        _load();
                      },
                    ),
                ]),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.robot.connected ? _explore : null,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Create a new map'),
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
  static String _pad(int n) => n.toString().padLeft(2, '0');
}
