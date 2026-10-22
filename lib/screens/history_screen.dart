import 'package:flutter/material.dart';

import '../api.dart';
import '../problems.dart';
import '../robot/robot_details.dart';

/// Earlier cleanings, like the "Runs" page in the Vacuula web app.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.api, required this.robot, this.initial});

  final VacuulaApi api;
  final RobotInfo robot;
  final List<CleaningRun>? initial;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late List<CleaningRun>? _runs = widget.initial;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_runs == null) _load();
  }

  Future<void> _load() async {
    try {
      final runs = await widget.api.cleaningRuns(widget.robot);
      if (mounted) {
        setState(() {
          _runs = runs;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final runs = _runs;
    return Scaffold(
      appBar: AppBar(title: Text('History · ${widget.robot.name}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: runs == null && _error == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  if (_error != null)
                    Card(
                      color: cs.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
                      ),
                    ),
                  if (runs != null && runs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No cleanings recorded yet. The server saves every cleaning the robot reports from now on.',
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  for (final r in runs ?? const <CleaningRun>[])
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          r.complete ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: r.complete ? cs.primary : cs.error,
                        ),
                        title: Text(formatDateTime(r.start)),
                        subtitle: Text([
                          formatDuration(r.duration),
                          formatArea(r.areaM2),
                          if (r.batteryUsed != null) '${r.batteryUsed} % battery',
                        ].join(' · ')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showRun(r),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  void _showRun(CleaningRun r) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        Widget row(String k, String v, {Color? color}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(k, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
                Expanded(child: Text(v, style: t.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600))),
              ]),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text(formatDateTime(r.start), style: t.titleLarge),
                const SizedBox(height: 12),
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
            ),
          ),
        );
      },
    );
  }

  static String _pretty(String s) {
    final v = s.replaceAll('_', ' ').replaceFirst(RegExp(r'^ui (error|alert) '), '');
    return v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);
  }
}
