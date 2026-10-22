import 'package:flutter/material.dart';

import '../api.dart';
import '../robot/robot_details.dart';
import 'history_screen.dart';

/// Name, battery health and statistics for one robot.
class RobotScreen extends StatefulWidget {
  const RobotScreen({super.key, required this.api, required this.robot, this.status});

  final VacuulaApi api;
  final RobotInfo robot;
  final RobotStatus? status;

  @override
  State<RobotScreen> createState() => _RobotScreenState();
}

class _RobotScreenState extends State<RobotScreen> {
  late final _name = TextEditingController(text: widget.robot.name);
  late String _savedName = widget.robot.name;
  bool _saving = false;

  List<CleaningRun>? _runs;
  String? _runsError;
  BatteryInfo? _battery;
  bool _batteryLoading = false;
  String? _batteryError;

  /// True when the name was changed, so the home screen reloads.
  bool _changed = false;

  RobotInfo get r => widget.robot;

  @override
  void initState() {
    super.initState();
    _loadRuns();
    if (r.gen == RobotGen.gen3 && r.connected) _loadBattery();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadRuns() async {
    try {
      final runs = await widget.api.cleaningRuns(r);
      if (mounted) setState(() => _runs = runs);
    } catch (e) {
      if (mounted) setState(() => _runsError = '$e');
    }
  }

  Future<void> _loadBattery() async {
    setState(() {
      _batteryLoading = true;
      _batteryError = null;
    });
    try {
      final b = await widget.api.batteryInfo(r);
      if (mounted) setState(() => _battery = b);
    } catch (e) {
      if (mounted) setState(() => _batteryError = '$e');
    } finally {
      if (mounted) setState(() => _batteryLoading = false);
    }
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty || name == _savedName) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.api.renameRobot(r, name);
      _savedName = name;
      _changed = true;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text(title, style: t.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
        );
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(k, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
            const SizedBox(width: 12),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          ]),
        );
    Widget card(List<Widget> children) => Card(
          margin: EdgeInsets.zero,
          child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Column(children: children)),
        );

    final birthday = r.gen == RobotGen.gen3 ? robotBirthday(r.serial) : null;
    final charge = widget.status?.charge;
    final dirty = _name.text.trim().isNotEmpty && _name.text.trim() != _savedName;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_savedName)),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          section('Name'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _saveName(),
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Robot name'),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: dirty && !_saving ? _saveName : null,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ]),
          section('Robot'),
          card([
            row('Model', r.model),
            row('Serial number', r.labelSerial ?? r.serial),
            if (birthday != null) row('Made', formatDate(birthday)),
          ]),
          if (r.gen == RobotGen.gen3) ...[
            section('Battery'),
            card([
              if (charge != null) row('Charge', '$charge %'),
              if (_batteryLoading) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
              if (!r.connected)
                row('Details', 'The robot is offline')
              else if (_batteryError != null)
                row('Details', 'Not available ($_batteryError)')
              else if (!_batteryLoading && _battery == null)
                row('Details', 'This robot does not report battery details')
              else if (_battery != null) ...[
                if (_battery!.timeToEmpty != null) row('Runtime left', formatDuration(Duration(minutes: _battery!.timeToEmpty!))),
                if (_battery!.timeToFullCharge != null)
                  row('Full in', formatDuration(Duration(minutes: _battery!.timeToFullCharge!))),
                if (_battery!.totalCharges != null) row('Charge cycles', '${_battery!.totalCharges}'),
                if (_battery!.manufacturingDate != null) row('Battery made', _battery!.manufacturingDate!),
                if (_battery!.vendor != null) row('Battery vendor', _battery!.vendor!),
                if (_battery!.authorization != null) row('Battery', _battery!.authorization!),
              ],
            ]),
            if (_battery?.totalCharges != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'If the runtime gets much shorter than when the battery was new, it may be time for a new battery.',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
          section('Statistics'),
          if (_runsError != null)
            card([row('Statistics', 'Not available ($_runsError)')])
          else if (_runs == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else
            _stats(card, row, CleaningTotals(_runs!)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => HistoryScreen(api: widget.api, robot: r, initial: _runs),
            )),
            icon: const Icon(Icons.history_rounded),
            label: const Text('Cleaning history'),
          ),
        ]),
      ),
    );
  }

  Widget _stats(Widget Function(List<Widget>) card, Widget Function(String, String) row, CleaningTotals s) {
    if (s.count == 0) return card([row('Cleanings', 'None recorded yet')]);
    return card([
      row('Cleanings', '${s.count} (${s.completed} completed)'),
      row('Total area', formatArea(s.areaM2)),
      row('Total time', formatDuration(s.time)),
      if (s.count > 0) row('Average', '${formatArea(s.areaM2 / s.count)} · ${formatDuration(s.time ~/ s.count)}'),
      if (s.first != null) row('Since', formatDate(s.first)),
    ]);
  }
}
