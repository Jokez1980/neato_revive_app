import 'package:flutter/material.dart';

import '../api.dart';

/// Bottom sheet for choosing how to clean: area, suction and navigation -
/// the same options as the Vacuula web app. Returns the new prefs and whether
/// to start right away, or null when cancelled.
Future<({CleaningPrefs prefs, bool start})?> showCleaningOptions(
  BuildContext context, {
  required RobotGen gen,
  required CleaningPrefs prefs,
  bool canStart = true,
}) {
  return showModalBottomSheet<({CleaningPrefs prefs, bool start})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CleaningOptions(gen: gen, initial: prefs, canStart: canStart),
  );
}

class _CleaningOptions extends StatefulWidget {
  const _CleaningOptions({required this.gen, required this.initial, required this.canStart});

  final RobotGen gen;
  final CleaningPrefs initial;
  final bool canStart;

  @override
  State<_CleaningOptions> createState() => _CleaningOptionsState();
}

class _CleaningOptionsState extends State<_CleaningOptions> {
  late CleaningPrefs _p = widget.initial;

  bool get _gen4 => widget.gen == RobotGen.gen4;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(s, style: t.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
        );
    Widget hint(String s) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(s, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        );

    final children = _gen4 ? _gen4Options(label, hint) : _gen3Options(label, hint);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cleaning options', style: t.titleLarge),
              ...children,
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, (prefs: _p, start: false)),
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.canStart ? () => Navigator.pop(context, (prefs: _p, start: true)) : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _gen3Options(Widget Function(String) label, Widget Function(String) hint) {
    final deep = _p.gen3Nav == 3;
    return [
      label('Where'),
      SegmentedButton<String>(
        segments: [
          for (final e in CleaningPrefs.gen3AreaNames.entries) ButtonSegment(value: e.key, label: Text(e.value)),
        ],
        selected: {_p.gen3Area},
        onSelectionChanged: (s) => setState(() => _p = _p.copyWith(gen3Area: s.first)),
      ),
      hint(switch (_p.gen3Area) {
        'map' => 'Uses your map: respects no-go lines and no-go areas. The robot must start from its base '
            '(otherwise it cleans the whole house).',
        'house' => 'Cleans everything it can reach. Ignores no-go lines and zones.',
        _ => 'Cleans a rectangle around where the robot stands now.',
      }),
      if (_p.gen3Area == 'spot') ...[
        const SizedBox(height: 8),
        _slider('Width', _p.spotWidth, (v) => setState(() => _p = _p.copyWith(spotWidth: v))),
        _slider('Length', _p.spotHeight, (v) => setState(() => _p = _p.copyWith(spotHeight: v))),
      ],
      label('Navigation'),
      SegmentedButton<int>(
        segments: [
          for (final e in CleaningPrefs.gen3NavNames.entries) ButtonSegment(value: e.key, label: Text(e.value)),
        ],
        selected: {_p.gen3Nav},
        onSelectionChanged: (s) => setState(() => _p = _p.copyWith(gen3Nav: s.first)),
      ),
      hint(switch (_p.gen3Nav) {
        2 => 'Extra care: gentler around furniture and walls.',
        3 => 'Deep: slower and more thorough, for carpets and dirty floors. Always uses Turbo suction.',
        _ => 'Normal: the standard cleaning pattern.',
      }),
      label('Suction'),
      SegmentedButton<int>(
        segments: [
          for (final e in CleaningPrefs.gen3ModeNames.entries)
            ButtonSegment(value: e.key, label: Text(e.value), enabled: !(deep && e.key == 1)),
        ],
        selected: {_p.gen3EffectiveMode},
        onSelectionChanged: (s) => setState(() => _p = _p.copyWith(gen3Mode: s.first)),
      ),
      hint(_p.gen3EffectiveMode == 1 ? 'Eco: quieter and runs longer on a charge.' : 'Turbo: full suction power ("Normal" in the Vacuula web app).'),
    ];
  }

  Widget _slider(String name, int value, ValueChanged<int> onChanged) => Row(children: [
        SizedBox(width: 64, child: Text(name)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 100,
            max: 400,
            divisions: 30,
            label: '$value cm',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 64, child: Text('$value cm', textAlign: TextAlign.right)),
      ]);

  List<Widget> _gen4Options(Widget Function(String) label, Widget Function(String) hint) => [
        label('Where'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Floorplan')),
            ButtonSegment(value: false, label: Text('Whole home')),
          ],
          selected: {_p.gen4UseMap},
          onSelectionChanged: (s) => setState(() => _p = _p.copyWith(gen4UseMap: s.first)),
        ),
        hint(_p.gen4UseMap
            ? 'Uses the floorplan in use: respects no-go lines and zones. Falls back to the whole home if there is none.'
            : 'Cleans everything it can reach. Ignores no-go lines and zones.'),
        label('Suction'),
        SegmentedButton<String>(
          segments: [
            for (final e in CleaningPrefs.gen4ModeNames.entries) ButtonSegment(value: e.key, label: Text(e.value)),
          ],
          selected: {_p.gen4Mode},
          onSelectionChanged: (s) => setState(() => _p = _p.copyWith(gen4Mode: s.first)),
        ),
        hint('Auto and Max are available on D10.'),
        label('Navigation'),
        SegmentedButton<String>(
          segments: [
            for (final e in CleaningPrefs.gen4NavNames.entries) ButtonSegment(value: e.key, label: Text(e.value)),
          ],
          selected: {_p.gen4Nav},
          onSelectionChanged: (s) => setState(() => _p = _p.copyWith(gen4Nav: s.first)),
        ),
        hint(_p.gen4Nav == 'gentle' ? 'Gentle: careful around furniture.' : 'Normal: the standard cleaning pattern.'),
      ];
}
