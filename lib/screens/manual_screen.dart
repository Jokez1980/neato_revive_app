import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../manual/manual_drive.dart';
import '../settings.dart';

/// The command that prints the robot's secret key on the Vacuula server
/// (run in the folder with Vacuula's docker-compose.yaml).
const secretKeyCommand =
    "docker compose exec vacuula python -c \"import sqlite3; "
    "[print(r[0], r[1]) for r in sqlite3.connect('/server/data/vacuula.db')"
    ".execute('select robot, password from gen3__data')]\"";

/// Remote control (manual driving) for Gen3 robots - the "manual mode" from the
/// old Neato app for Botvac Connected and D3-D7.
class ManualScreen extends StatefulWidget {
  const ManualScreen({super.key, required this.api, required this.robot, required this.settings});

  final VacuulaApi api;
  final RobotInfo robot;
  final AppSettings settings;

  @override
  State<ManualScreen> createState() => _ManualScreenState();
}

enum _Phase { needKey, idle, connecting, connected }

class _ManualScreenState extends State<ManualScreen> {
  late _Phase _phase = widget.settings.manualKey(widget.robot.serial) == null ? _Phase.needKey : _Phase.idle;
  final _keyCtl = TextEditingController();
  ManualDrive? _drive;
  String? _error;
  String? _lastMessage;
  StreamSubscription<String>? _msgSub;
  DriveCombo? _held;

  bool _brush = true;
  bool _vacuum = true;
  bool _eco = false;

  @override
  void dispose() {
    _keyCtl.dispose();
    _msgSub?.cancel();
    _drive?.close();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final k = _keyCtl.text.trim();
    if (k.isEmpty) return;
    await widget.settings.setManualKey(widget.robot.serial, k);
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  Future<void> _connect() async {
    final key = widget.settings.manualKey(widget.robot.serial);
    if (key == null) {
      setState(() => _phase = _Phase.needKey);
      return;
    }
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
    });
    try {
      final d = await ManualDrive.connect(widget.api, widget.robot, key);
      if (!mounted) {
        await d.close();
        return;
      }
      _drive = d;
      _msgSub = d.messages.listen((m) {
        if (mounted) setState(() => _lastMessage = m);
      });
      d.done.then((_) {
        if (mounted && _drive == d) {
          setState(() {
            _drive = null;
            _phase = _Phase.idle;
            _error ??= 'The robot ended remote control (it stops after 30 s without commands, or when it is picked up).';
          });
        }
      });
      setState(() => _phase = _Phase.connected);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _disconnect() async {
    final d = _drive;
    _drive = null;
    await _msgSub?.cancel();
    await d?.close();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  void _press(DriveCombo c) {
    HapticFeedback.selectionClick();
    setState(() => _held = c);
    _drive?.startMoving(c);
  }

  void _release() {
    if (_held == null) return;
    setState(() => _held = null);
    _drive?.stopMoving();
  }

  void _toggle(DriveCommand on, DriveCommand off, bool value) {
    HapticFeedback.selectionClick();
    _drive?.send(value ? on : off);
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _drive?.close(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Remote control · ${widget.robot.name}'),
          actions: [
            if (_phase != _Phase.needKey)
              IconButton(
                tooltip: 'Secret key',
                icon: const Icon(Icons.key_rounded),
                onPressed: _phase == _Phase.connected
                    ? null
                    : () => setState(() {
                          _keyCtl.text = widget.settings.manualKey(widget.robot.serial) ?? '';
                          _phase = _Phase.needKey;
                        }),
              ),
          ],
        ),
        body: SafeArea(
          child: switch (_phase) {
            _Phase.needKey => _keySetup(),
            _Phase.connected => _controls(),
            _ => _start(),
          },
        ),
      ),
    );
  }

  Widget _keySetup() {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('One-time setup', style: t.titleLarge),
      const SizedBox(height: 8),
      Text(
        'Remote control talks directly to the robot, and the robot only accepts it when it is signed '
        'with the robot\'s secret key. Your Vacuula server has the key - copy it into the app once:',
        style: t.bodyMedium,
      ),
      const SizedBox(height: 16),
      Text('1. On the computer running Vacuula, in the folder with its docker-compose.yaml, run:',
          style: t.bodyMedium),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        child: SelectableText(secretKeyCommand, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: secretKeyCommand));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Command copied')));
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy command'),
        ),
      ),
      Text(
        '2. It prints one line per robot: the serial number and the key. '
        'Copy the key on the line with ${widget.robot.serial} and paste it here:',
        style: t.bodyMedium,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _keyCtl,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'Secret key', border: OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _keyCtl.text.trim().isEmpty ? null : _saveKey, child: const Text('Save key')),
      const SizedBox(height: 16),
      Text(
        'The key is stored only in this app on this phone. Anyone with it can control the robot on your '
        'network, so don\'t share it.',
        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    ]);
  }

  Widget _start() {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final connecting = _phase == _Phase.connecting;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Icon(Icons.sports_esports_outlined, size: 56, color: cs.primary),
      const SizedBox(height: 12),
      Text('Drive the robot yourself', textAlign: TextAlign.center, style: t.titleLarge),
      const SizedBox(height: 8),
      Text(
        'The robot must be idle (not cleaning) and your phone on the same Wi-Fi as the robot. '
        'Hold a direction to move; let go to stop.',
        textAlign: TextAlign.center,
        style: t.bodyMedium,
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: connecting ? null : _connect,
        icon: connecting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.play_arrow_rounded),
        label: Text(connecting ? 'Connecting…' : 'Start remote control'),
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        Card(
          color: cs.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: t.bodyMedium?.copyWith(color: cs.onErrorContainer)),
          ),
        ),
      ],
      const SizedBox(height: 24),
      Text(
        'Experimental: this uses the same remote-control feature as the old Neato app '
        '(Botvac Connected, D3-D7).',
        textAlign: TextAlign.center,
        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    ]);
  }

  Widget _controls() {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final info = _drive?.info;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Icon(Icons.circle, size: 10, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Connected to ${info?.ip}', style: t.bodyMedium)),
          TextButton(onPressed: _disconnect, child: const Text('End')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
          FilterChip(
            label: const Text('Brush'),
            selected: _brush,
            onSelected: (v) {
              setState(() => _brush = v);
              _toggle(DriveCommand.brushOn, DriveCommand.brushOff, v);
            },
          ),
          FilterChip(
            label: const Text('Vacuum'),
            selected: _vacuum,
            onSelected: (v) {
              setState(() => _vacuum = v);
              _toggle(DriveCommand.vacuumOn, DriveCommand.vacuumOff, v);
            },
          ),
          FilterChip(
            label: const Text('Eco'),
            selected: _eco,
            onSelected: (v) {
              setState(() => _eco = v);
              _drive?.send(v ? DriveCommand.ecoOn : DriveCommand.turboOn);
            },
          ),
        ]),
      ),
      Expanded(
        child: Center(
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _pad(DriveCombo.arcLeft, Icons.turn_left_rounded, 'Arc left'),
                  _pad(DriveCombo.forward, Icons.arrow_upward_rounded, 'Forward', big: true),
                  _pad(DriveCombo.arcRight, Icons.turn_right_rounded, 'Arc right'),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _pad(DriveCombo.pivotLeft, Icons.rotate_left_rounded, 'Turn left'),
                  _stopButton(cs),
                  _pad(DriveCombo.pivotRight, Icons.rotate_right_rounded, 'Turn right'),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 104),
                  _pad(DriveCombo.back, Icons.arrow_downward_rounded, 'Back'),
                  const SizedBox(width: 104),
                ]),
              ]),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          _lastMessage == null
              ? 'Hold a button to move, let go to stop. "Back" moves about 30 cm at a time.'
              : 'Robot: $_lastMessage',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    ]);
  }

  Widget _pad(DriveCombo c, IconData icon, String label, {bool big = false}) {
    final cs = Theme.of(context).colorScheme;
    final held = _held == c;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Listener(
        onPointerDown: (_) => _press(c),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: held ? cs.primary : cs.secondaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: big ? 44 : 36, color: held ? cs.onPrimary : cs.onSecondaryContainer),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 11, color: held ? cs.onPrimary : cs.onSecondaryContainer)),
          ]),
        ),
      ),
    );
  }

  Widget _stopButton(ColorScheme cs) => Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          width: 92,
          height: 92,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(46)),
              padding: EdgeInsets.zero,
            ),
            onPressed: () {
              HapticFeedback.heavyImpact();
              setState(() => _held = null);
              _drive?.stopMoving();
            },
            child: const Text('STOP', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      );
}
