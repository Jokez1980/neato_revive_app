import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../settings.dart';
import '../watch.dart';
import '../widgets/robot_card.dart';
import 'maps_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  VacuulaApi? _api;
  List<RobotInfo> _robots = [];
  final Map<String, RobotStatus> _status = {};
  final Map<String, RobotCommand> _busy = {};
  String? _serverError;
  bool _loading = false;
  bool _firstLoadDone = false;
  Timer? _timer;
  bool _inForeground = true;
  int _generation = 0; // ignorerar gamla svar efter byte av server

  AppSettings get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_onSettingsChanged);
    _api = settings.hasServer ? VacuulaApi(settings.server) : null;
    // Make sure the background watcher runs if notifications are on
    RobotWatcher.apply(enabled: settings.notifications, server: settings.server);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (settings.hasServer) {
        _refresh();
      } else {
        _openSettings();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    settings.removeListener(_onSettingsChanged);
    _timer?.cancel();
    _api?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (_inForeground) {
      _refresh();
    } else {
      _timer?.cancel();
    }
  }

  void _onSettingsChanged() => _connect();

  void _connect() {
    _api?.close();
    _api = settings.hasServer ? VacuulaApi(settings.server) : null;
    _generation++;
    setState(() {
      _robots = [];
      _status.clear();
      _serverError = null;
      _firstLoadDone = false;
    });
    _refresh();
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null) return;
    final gen = _generation;
    _timer?.cancel();
    setState(() => _loading = true);

    try {
      final robots = await api.robots();
      if (!mounted || gen != _generation) return;
      setState(() {
        _robots = robots;
        _serverError = null;
      });
      await Future.wait(robots.map((r) async {
        if (!r.connected || r.gen == RobotGen.unknown) {
          _status.remove(r.serial);
          return;
        }
        try {
          final s = await api.state(r);
          if (mounted && gen == _generation) _status[r.serial] = s;
        } catch (_) {
          // behåll senast kända status
        }
      }));
    } catch (e) {
      if (!mounted || gen != _generation) return;
      _robots = [];
      _serverError = e.toString();
    }

    if (!mounted || gen != _generation) return;
    setState(() {
      _loading = false;
      _firstLoadDone = true;
    });
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_inForeground || _api == null) return;
    final active = _status.values.any((s) => s.isActive);
    _timer = Timer(Duration(seconds: active ? 4 : 10), _refresh);
  }

  static const _doneText = {
    RobotCommand.start: 'Cleaning started',
    RobotCommand.resume: 'Resuming cleaning',
    RobotCommand.pause: 'Paused',
    RobotCommand.stop: 'Stopped',
    RobotCommand.base: 'Returning to base',
    RobotCommand.find: 'The vacuum is beeping',
  };

  Future<void> _run(RobotInfo robot, RobotCommand cmd) async {
    final api = _api;
    if (api == null || _busy.containsKey(robot.serial)) return;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _busy[robot.serial] = cmd);
    try {
      await api.run(robot, cmd, settings.cleaning);
      messenger.showSnackBar(SnackBar(content: Text(_doneText[cmd]!)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: errorColor,
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(robot.serial));
    }
    // Ge roboten en stund att byta läge innan vi frågar igen
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) _refresh();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(settings: settings),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hostLabel = settings.server.replaceFirst(RegExp(r'^https?://'), '');

    final Color dotColor;
    final String subtitle;
    if (!settings.hasServer) {
      dotColor = cs.outline;
      subtitle = 'No server selected';
    } else if (_serverError != null) {
      dotColor = cs.error;
      subtitle = 'Cannot reach $hostLabel';
    } else if (!_firstLoadDone) {
      dotColor = cs.outline;
      subtitle = 'Connecting to $hostLabel…';
    } else {
      dotColor = cs.primary;
      subtitle = hostLabel;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(children: [
          Image.asset('assets/logo.png', height: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Vacuula', style: TextStyle(fontWeight: FontWeight.w700)),
                Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ]),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: _content(context),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    if (!settings.hasServer) {
      return [
        _EmptyState(
          icon: Icons.dns_outlined,
          title: 'Set up your server',
          text: 'Enter the address of your Vacuula server, or let the app search for it on your home network.',
          actionLabel: 'Open settings',
          onAction: _openSettings,
        ),
      ];
    }
    if (_serverError != null) {
      return [
        _EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Cannot reach the server',
          text: '$_serverError.\n\nMake sure your phone is on your home network (or VPN) '
              'and that the address ${settings.server} is correct.',
          actionLabel: 'Try again',
          onAction: _refresh,
          secondaryLabel: 'Settings',
          onSecondary: _openSettings,
        ),
      ];
    }
    if (!_firstLoadDone) {
      return const [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator()),
      ];
    }
    if (_robots.isEmpty) {
      return [
        _EmptyState(
          icon: Icons.cleaning_services_outlined,
          title: 'No vacuums found',
          text: 'The server responds, but no robot is linked yet. '
              'Set up your robot with the Vacuula installer first.',
          actionLabel: 'Refresh',
          onAction: _refresh,
        ),
      ];
    }
    return [
      for (final r in _robots)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: RobotCard(
            robot: r,
            status: _status[r.serial],
            busy: _busy[r.serial],
            onCommand: (c) => _run(r, c),
            onMaps: _api == null || r.gen == RobotGen.unknown
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => MapsScreen(api: _api!, robot: r, settings: settings),
                    )),
            onSchedule: _api == null || r.gen == RobotGen.unknown || !r.connected
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ScheduleScreen(api: _api!, robot: r),
                    )),
          ),
        ),
    ];
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          children: [
            Icon(icon, size: 40, color: cs.primary),
            const SizedBox(height: 12),
            Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
                if (secondaryLabel != null)
                  OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
