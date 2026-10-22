import '../api.dart';
import '../problems.dart';

/// Something worth a notification.
class RobotEvent {
  const RobotEvent(this.title, this.body, {this.important = false});
  final String title;
  final String body;

  /// Shown as a high-priority alert (needs help, dust bin, offline during a run).
  final bool important;

  @override
  String toString() => '${important ? '[!] ' : ''}$title | $body';
}

const _activeJobs = {
  'cleaning', 'cleaning_standby', 'docking', 'exploring', 'exploration_suspended',
  'creating_map', 'acquiring_map_ids', 'recovering_location',
};

/// Follows one robot over time and turns status changes into events.
/// Pure Dart, no Flutter - easy to test (see test/robot_events_test.dart).
class RobotTracker {
  RobotTracker(this.name, {this.offlineAfter = const Duration(minutes: 3)});

  String name;
  final Duration offlineAfter;

  RobotStatus? _prev;
  bool _job = false; // a cleaning or mapping run is going on
  bool _exploring = false; // the run is a mapping run
  String? _errorReported;
  String? _alertReported;
  bool _online = true;
  DateTime? _offlineSince;
  bool _offlineReported = false;

  String _battery(RobotStatus s) => s.charge == null ? '' : ' Battery ${s.charge}%.';

  List<RobotEvent> update(RobotStatus s) {
    final events = <RobotEvent>[];
    final p = _prev;
    _prev = s;
    final st = s.state, act = s.action;

    // First look at the robot: just remember, only report existing problems
    if (p == null) {
      _job = (st == 'busy' || st == 'paused') && _activeJobs.contains(act);
      _exploring = act.startsWith('explor');
      _problems(s, events);
      return events;
    }

    if (st == 'busy' && act == 'cleaning' && !_job) {
      _job = true;
      _exploring = false;
      events.add(RobotEvent('$name started cleaning', 'Cleaning has started.${_battery(s)}'));
    } else if (st == 'busy' && act == 'exploring' && !_job) {
      _job = true;
      _exploring = true;
      events.add(RobotEvent('$name is mapping', 'Exploring your home to create a map.'));
    }

    if (act == 'cleaning_standby' && p.action != 'cleaning_standby') {
      _job = true;
      events.add(RobotEvent('$name is recharging',
          'Returned to base to recharge. Cleaning will continue automatically.${_battery(s)}'));
    } else if (p.action == 'cleaning_standby' && act == 'cleaning' && st == 'busy') {
      events.add(RobotEvent('$name resumed cleaning', 'Recharged and back to work.${_battery(s)}'));
    }

    if (st == 'paused' && p.state != 'paused') {
      events.add(RobotEvent('$name paused', 'Cleaning is paused.'));
    } else if (p.state == 'paused' && st == 'busy') {
      events.add(RobotEvent('$name resumed', 'Back to work.'));
    }

    if (_job && st == 'idle') {
      _job = false;
      if (_exploring) {
        events.add(RobotEvent('$name finished mapping', 'Mapping is done.${_battery(s)}'));
      } else if (s.docked || s.charging) {
        events.add(RobotEvent('$name finished cleaning',
            'Cleaning is done and the robot is back on the base.${_battery(s)}'));
      } else {
        events.add(RobotEvent('$name stopped',
            'Cleaning was stopped before it reached the base.${_battery(s)}'));
      }
      _exploring = false;
    }

    _problems(s, events);
    return events;
  }

  void _problems(RobotStatus s, List<RobotEvent> events) {
    var err = s.error;
    if (s.state == 'error' && err == null) err = 'unknown';
    if (err != null && err != _errorReported) {
      _errorReported = err;
      events.add(RobotEvent('$name needs help',
          err == 'unknown' ? 'The robot reports an error.' : '${problemText(err)}.',
          important: true));
    } else if (err == null) {
      _errorReported = null;
    }

    final alert = s.alert;
    if (alert != null && alert != _alertReported) {
      _alertReported = alert;
      events.add(RobotEvent(name, '${problemText(alert)}.', important: true));
    } else if (alert == null) {
      _alertReported = null;
    }
  }

  /// Call every check with whether the server says the robot is connected.
  List<RobotEvent> markOnline(bool online, {DateTime? now}) {
    now ??= DateTime.now();
    if (online) {
      final back = _offlineReported;
      _online = true;
      _offlineSince = null;
      _offlineReported = false;
      return back
          ? [RobotEvent('$name is back online', 'The robot is connected to the server again.')]
          : const [];
    }
    if (_online) {
      _online = false;
      _offlineSince = now;
    }
    final since = _offlineSince;
    if (!_offlineReported && since != null && now.difference(since) >= offlineAfter) {
      _offlineReported = true;
      return [
        RobotEvent('$name is offline',
            'Not connected to the server for ${offlineAfter.inMinutes} minutes. '
            'Out of battery, stuck under something or off Wi-Fi?',
            important: _job),
      ];
    }
    return const [];
  }
}
