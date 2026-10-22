import 'package:flutter/material.dart';

import '../api.dart';
import '../discovery.dart';
import '../settings.dart';
import '../watch.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _TestState { none, testing, ok, failed }

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _server =
      TextEditingController(text: widget.settings.server);
  late bool _notifications = widget.settings.notifications;

  _TestState _test = _TestState.none;
  String _testMessage = '';

  bool _scanning = false;
  double _scanProgress = 0;
  List<FoundServer>? _found;

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final url = VacuulaApi.normalizeUrl(_server.text);
    if (url.isEmpty) return;
    setState(() => _test = _TestState.testing);
    final api = VacuulaApi(url);
    try {
      final info = await api.serverInfo();
      final robots = await api.robots();
      if (!mounted) return;
      setState(() {
        _test = _TestState.ok;
        _testMessage = 'Vacuula ${info['version']} · '
            '${robots.length} ${robots.length == 1 ? 'robot' : 'robots'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _test = _TestState.failed;
        _testMessage = '$e';
      });
    } finally {
      api.close();
    }
  }

  Future<void> _scan() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _scanning = true;
      _scanProgress = 0;
      _found = null;
    });
    List<FoundServer> found;
    try {
      found = await findVacuulaServers(
        onProgress: (p) {
          if (mounted) setState(() => _scanProgress = p);
        },
      );
    } catch (_) {
      found = [];
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _found = found;
    });
    if (found.length == 1) _pick(found.first);
  }

  void _pick(FoundServer s) {
    _server.text = s.url;
    setState(() {
      _test = _TestState.ok;
      _testMessage = 'Vacuula ${s.version}';
    });
  }

  Future<void> _save() async {
    await widget.settings.save(
      server: _server.text,
      notifications: _notifications,
    );
    await RobotWatcher.apply(enabled: _notifications, server: widget.settings.server);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 10),
          child: Text(title, style: t.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          section('Vacuula server'),
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _test = _TestState.none),
            onSubmitted: (_) => _testConnection(),
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: '192.168.1.23',
              helperText: 'IP address of the computer running Vacuula. Add :port if you changed VACUULA_PORT.',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: const Icon(Icons.radar),
                label: const Text('Search network'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _test == _TestState.testing ? null : _testConnection,
                icon: _test == _TestState.testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check),
                label: const Text('Test'),
              ),
            ),
          ]),
          if (_test == _TestState.ok || _test == _TestState.failed) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(
                _test == _TestState.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: _test == _TestState.ok ? cs.primary : cs.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _test == _TestState.ok ? 'Connected: $_testMessage' : _testMessage,
                  style: t.bodyMedium?.copyWith(color: _test == _TestState.ok ? cs.primary : cs.error),
                ),
              ),
            ]),
          ],
          if (_scanning) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(value: _scanProgress),
            const SizedBox(height: 6),
            Text('Searching for Vacuula on your home network…', style: t.bodySmall),
          ],
          if (!_scanning && _found != null) ...[
            const SizedBox(height: 12),
            if (_found!.isEmpty)
              Text(
                'No server found. Make sure your phone is on the same Wi-Fi as the server, '
                'that Vacuula is running and that the app has local network access.',
                style: t.bodySmall?.copyWith(color: cs.error),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(children: [
                  for (final s in _found!)
                    ListTile(
                      leading: const Icon(Icons.dns_rounded),
                      title: Text(s.url.replaceFirst('http://', '')),
                      subtitle: Text('Vacuula ${s.version}'),
                      trailing: VacuulaApi.normalizeUrl(_server.text) == s.url
                          ? Icon(Icons.check_rounded, color: cs.primary)
                          : null,
                      onTap: () => _pick(s),
                    ),
                ]),
              ),
          ],
          if (RobotWatcher.supported) ...[
            section('Notifications'),
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                SwitchListTile(
                  value: _notifications,
                  onChanged: (v) async {
                    setState(() => _notifications = v);
                    if (v) await RobotWatcher.requestPermission();
                  },
                  title: const Text('Notify me'),
                  subtitle: const Text(
                    'When a robot starts, recharges, finishes, needs help or goes offline. '
                    'Works while your phone is on the home network (or VPN).',
                  ),
                ),
                if (_notifications)
                  ListTile(
                    leading: Icon(Icons.battery_alert_rounded, color: cs.primary),
                    title: const Text('Tip: let it run in the background'),
                    subtitle: const Text(
                      'Android settings > Apps > Neato Revive App > Battery > Unrestricted, '
                      'so the phone does not stop the watcher.',
                    ),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _server.text.trim().isEmpty ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
