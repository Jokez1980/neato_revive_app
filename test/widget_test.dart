import 'package:vacuula/api.dart';
import 'package:vacuula/widgets/robot_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Gen3 status', () {
    final s = RobotStatus.fromGen3({
      'state': 2,
      'action': 1,
      'details': {'charge': 76, 'isCharging': false, 'isDocked': false},
      'availableCommands': {'start': false, 'stop': true, 'pause': true, 'resume': false, 'goToBase': false},
    });
    expect(s.state, 'busy');
    expect(s.action, 'cleaning');
    expect(s.charge, 76);
    expect(s.can.stop, isTrue);
    expect(s.can.start, isFalse);
  });

  test('Gen3 charging during cleaning', () {
    final s = RobotStatus.fromGen3({'state': 2, 'action': 6, 'details': {'charge': 40, 'isCharging': true}});
    expect(s.action, 'cleaning_standby');
    expect(s.charging, isTrue);
  });

  test('parses Gen4 status', () {
    final s = RobotStatus.fromGen4({
      'type': 'response',
      'code': 200,
      'body': {
        'state': 'paused',
        'action': 'cleaning',
        'errors': [
          {'code': 'lw_hanging', 'severity': 'error'}
        ],
        'details': {'charge': 12.0, 'is_charging': true, 'is_docked': true},
        'available_commands': {'start': false, 'cancel': true, 'pause': false, 'resume': true, 'return_to_base': true},
      },
    });
    expect(s.state, 'paused');
    expect(s.charge, 12);
    expect(s.can.resume, isTrue);
    expect(s.error, 'lw_hanging');
  });

  test('normalizes server address', () {
    expect(VacuulaApi.normalizeUrl(' 192.168.1.5/ '), 'http://192.168.1.5');
    expect(VacuulaApi.normalizeUrl('https://x.local:8080'), 'https://x.local:8080');
  });

  testWidgets('robot card shows status and buttons', (tester) async {
    RobotCommand? pressed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RobotCard(
            robot: RobotInfo(serial: 'S1', gen: RobotGen.gen4, name: 'Kitchen', connected: true),
            status: const RobotStatus(
              state: 'idle',
              action: '',
              charge: 80,
              docked: true,
              can: RobotCaps(start: true, base: true),
            ),
            busy: null,
            onCommand: (c) => pressed = c,
          ),
        ),
      ),
    ));
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Docked'), findsOneWidget);
    await tester.tap(find.text('Start cleaning'));
    expect(pressed, RobotCommand.start);
  });
}
