import 'package:flutter/material.dart';

import '../api.dart';
import '../problems.dart';

String _problem(String code) => problemText(code);

enum _Tone { neutral, active, warn, error }

(String, _Tone) _statusText(RobotInfo r, RobotStatus? s) {
  if (!r.connected) return ('Not connected to the server', _Tone.error);
  if (s == null) return ('Fetching status…', _Tone.neutral);
  switch (s.state) {
    case 'error':
      return ('Error: ${s.error != null ? _problem(s.error!) : 'unknown'}', _Tone.error);
    case 'paused':
      return ('Paused', _Tone.warn);
    case 'busy':
      return switch (s.action) {
        'cleaning' => ('Cleaning', _Tone.active),
        'cleaning_standby' => ('Charging during cleaning', _Tone.active),
        'docking' => ('Docking', _Tone.active),
        'updating_software' => ('Updating', _Tone.active),
        'diagnostic_test' => ('Diagnostic test', _Tone.active),
        'copying_logs' => ('Copying logs', _Tone.active),
        'recovering_location' => ('Recovering location', _Tone.active),
        'exploring' => ('Exploring map', _Tone.active),
        'acquiring_map_ids' => ('Acquiring map IDs', _Tone.active),
        'creating_map' => ('Creating map', _Tone.active),
        'exploration_suspended' => ('Exploration suspended', _Tone.warn),
        _ => ('Busy', _Tone.active),
      };
  }
  if (s.charging) return ('Charging on base', _Tone.neutral);
  if (s.docked) return ('Docked', _Tone.neutral);
  return ('Idle', _Tone.neutral);
}

IconData _batteryIcon(int c, bool charging) {
  if (charging) return Icons.battery_charging_full_rounded;
  if (c >= 90) return Icons.battery_full_rounded;
  if (c >= 75) return Icons.battery_6_bar_rounded;
  if (c >= 60) return Icons.battery_5_bar_rounded;
  if (c >= 45) return Icons.battery_4_bar_rounded;
  if (c >= 30) return Icons.battery_3_bar_rounded;
  if (c >= 15) return Icons.battery_2_bar_rounded;
  if (c >= 5) return Icons.battery_1_bar_rounded;
  return Icons.battery_0_bar_rounded;
}

class RobotCard extends StatelessWidget {
  const RobotCard({
    super.key,
    required this.robot,
    required this.status,
    required this.busy,
    required this.onCommand,
    this.onMaps,
    this.onSchedule,
  });

  final RobotInfo robot;
  final RobotStatus? status;
  final RobotCommand? busy;
  final ValueChanged<RobotCommand> onCommand;

  /// Opens the maps of this robot (no button when null).
  final VoidCallback? onMaps;

  /// Opens the cleaning schedule of this robot (no button when null).
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final s = status;
    final can = (s != null && robot.connected) ? s.can : const RobotCaps();
    final (text, tone) = _statusText(robot, s);
    final toneColor = switch (tone) {
      _Tone.active => cs.primary,
      _Tone.warn => Colors.orange.shade700,
      _Tone.error => cs.error,
      _Tone.neutral => cs.onSurfaceVariant,
    };
    final paused = s?.state == 'paused';
    final idle = busy == null;

    bool enabled(bool allowed) => allowed && idle && robot.connected;

    Widget icon(RobotCommand c, IconData i) => busy == c
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(i);

    final charge = s?.charge;
    final charging = s?.charging ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(robot.name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${robot.model} · ${robot.labelSerial ?? robot.serial}',
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (charge != null)
                  Row(children: [
                    Icon(
                      _batteryIcon(charge, charging),
                      color: charge < 20 && !charging ? cs.error : cs.primary,
                    ),
                    const SizedBox(width: 2),
                    Text('$charge %', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ]),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: toneColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.circle, size: 10, color: toneColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s?.alert != null ? '$text · ${_problem(s!.alert!)}' : text,
                    style: t.bodyLarge?.copyWith(color: toneColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 60,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  textStyle: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: enabled(paused ? can.resume : can.start)
                    ? () => onCommand(paused ? RobotCommand.resume : RobotCommand.start)
                    : null,
                icon: icon(paused ? RobotCommand.resume : RobotCommand.start, Icons.play_arrow_rounded),
                label: Text(paused ? 'Resume' : 'Start cleaning'),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              _SmallButton(
                label: 'Pause',
                icon: icon(RobotCommand.pause, Icons.pause_rounded),
                onPressed: enabled(can.pause) ? () => onCommand(RobotCommand.pause) : null,
              ),
              const SizedBox(width: 10),
              _SmallButton(
                label: 'Stop',
                icon: icon(RobotCommand.stop, Icons.stop_rounded),
                color: cs.error,
                onPressed: enabled(can.stop) ? () => onCommand(RobotCommand.stop) : null,
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _SmallButton(
                label: 'Go to base',
                icon: icon(RobotCommand.base, Icons.home_outlined),
                onPressed: enabled(can.base) ? () => onCommand(RobotCommand.base) : null,
              ),
              const SizedBox(width: 10),
              _SmallButton(
                label: 'Find me',
                icon: icon(RobotCommand.find, Icons.notifications_active_outlined),
                onPressed: enabled(true) ? () => onCommand(RobotCommand.find) : null,
              ),
            ]),
            if (onMaps != null || onSchedule != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                if (onMaps != null)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onMaps,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Maps & zones'),
                    ),
                  ),
                if (onSchedule != null)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onSchedule,
                      icon: const Icon(Icons.event_repeat_rounded),
                      label: const Text('Schedule'),
                    ),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 50,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onPressed,
          icon: icon,
          label: Text(label),
        ),
      ),
    );
  }
}
