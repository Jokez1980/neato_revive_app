import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../api.dart';

/// Movements the robot understands in manual mode.
/// Send them repeatedly (at least once a second) while moving; the robot stops
/// by itself when they stop coming.
enum DriveCombo {
  forward('forward'),
  back('back'), // backs up ~30 cm per step (no sensors at the back)
  arcLeft('arc-left'),
  arcRight('arc-right'),
  pivotLeft('pivot-left'),
  pivotRight('pivot-right'),
  stop('stop');

  const DriveCombo(this.wire);
  final String wire;
}

/// On/off switches in manual mode.
enum DriveCommand {
  brushOn('brush-on'),
  brushOff('brush-off'),
  vacuumOn('vacuum-on'),
  vacuumOff('vacuum-off'),
  ecoOn('eco-on'),
  ecoOff('eco-off'),
  turboOn('turbo-on'),
  turboOff('turbo-off');

  const DriveCommand(this.wire);
  final String wire;
}

/// Where the robot accepts manual driving (from getRobotManualCleaningInfo).
class ManualInfo {
  ManualInfo({required this.ip, required this.port, this.ssid, this.validForSeconds});
  final String ip;
  final int port;
  final String? ssid;
  final int? validForSeconds;
}

class ManualDriveException implements Exception {
  ManualDriveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `Authorization: NEATOAPP <hmac>` for the robot's /drive websocket:
/// HMAC-SHA256 over `"<serial lowercase>\n<date>\n"` with the robot's secret key.
/// Same scheme the Vacuula server uses to sign commands (gen3/commands.py) and
/// the FHEM BOTVAC module uses for manual cleaning.
String signDriveHandshake(String serial, String date, String secretKey) {
  final msg = '${serial.toLowerCase()}\n$date\n';
  return Hmac(sha256, utf8.encode(secretKey)).convert(utf8.encode(msg)).toString();
}

/// Direct websocket connection to a Gen3 robot (Botvac Connected / D3-D7) for
/// remote-control driving. The phone must be on the same network as the robot.
class ManualDrive {
  ManualDrive._(this._ws, this.info, this._client) {
    _sub = _ws.listen(
      (m) => _messages.add(m is String ? m : utf8.decode(m as List<int>, allowMalformed: true)),
      onDone: _markClosed,
      onError: (Object e) => _markClosed(),
      cancelOnError: true,
    );
    // The robot leaves manual mode after ~30 s without messages: keep it alive while idle
    _keepAlive = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_moving == null) send(DriveCombo.stop);
    });
  }

  final WebSocket _ws;
  final HttpClient _client;
  final ManualInfo info;
  late final StreamSubscription<dynamic> _sub;
  late final Timer _keepAlive;
  Timer? _repeat;
  DriveCombo? _moving;
  final _messages = StreamController<String>.broadcast();
  final _closed = Completer<void>();

  void _markClosed() {
    _repeat?.cancel();
    if (!_closed.isCompleted) _closed.complete();
  }

  /// Text the robot sends back (if any) - shown for troubleshooting.
  Stream<String> get messages => _messages.stream;

  /// Completes when the connection is gone.
  Future<void> get done => _closed.future;
  bool get isOpen => !_closed.isCompleted;

  /// Asks the robot (through the Vacuula server) to open manual mode, then
  /// connects to it directly.
  static Future<ManualDrive> connect(VacuulaApi api, RobotInfo robot, String secretKey) async {
    if (robot.gen != RobotGen.gen3) {
      throw ManualDriveException('Remote control is only available on D3-D7 (Gen3) robots.');
    }
    final res = await api.command(robot.serial, {'cmd': 'getRobotManualCleaningInfo'});
    final data = (res is Map && res['data'] is Map) ? (res['data'] as Map) : null;
    if (data == null || data['ip_address'] is! String || data['port'] is! num) {
      final result = res is Map ? res['result'] : null;
      throw ManualDriveException(
          'The robot did not start manual mode${result != null && result != 'ok' ? ' ($result)' : ''}. '
          'It must be idle (not cleaning) and support remote control.');
    }
    final info = ManualInfo(
      ip: data['ip_address'] as String,
      port: (data['port'] as num).toInt(),
      ssid: data['ssid'] as String?,
      validForSeconds: (data['valid_for_seconds'] as num?)?.toInt(),
    );
    return open(robot.serial, info, secretKey);
  }

  /// Opens the signed websocket to ws://ip:port/drive.
  ///
  /// The handshake is done by hand instead of with WebSocket.connect, because
  /// Dart sends header names in lower case ("authorization:") and the robot's
  /// small web server only understands them spelled exactly like the Neato app
  /// does ("Authorization:") - otherwise it answers "invalid authorization header".
  static Future<ManualDrive> open(String serial, ManualInfo info, String secretKey) async {
    final path = 'ws://${info.ip}:${info.port}/drive';
    final date = HttpDate.format(DateTime.now().toUtc());
    final key = cleanSecretKey(secretKey);
    final wsKey = base64.encode(List<int>.generate(16, (_) => _rnd.nextInt(256)));
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = null
      ..autoUncompress = false;
    try {
      final req = await client
          .openUrl('GET', Uri.parse('http://${info.ip}:${info.port}/drive'))
          .timeout(const Duration(seconds: 8));
      req.followRedirects = false;
      final h = req.headers;
      h.removeAll(HttpHeaders.acceptEncodingHeader);
      void set(String name, String value) => h.set(name, value, preserveHeaderCase: true);
      set('Host', '${info.ip}:${info.port}');
      set('Sec-WebSocket-Key', wsKey);
      set('Sec-WebSocket-Version', '13');
      set('Upgrade', 'websocket');
      set('Origin', path);
      set('Date', date);
      set('Authorization', 'NEATOAPP ${signDriveHandshake(serial, date, key)}');
      set('Connection', 'Upgrade');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != HttpStatus.switchingProtocols) {
        final body = (await utf8.decodeStream(res).timeout(const Duration(seconds: 3), onTimeout: () => ''))
            .trim();
        client.close(force: true);
        final why = body.isNotEmpty ? body : '${res.statusCode} ${res.reasonPhrase}';
        throw ManualDriveException(res.statusCode == 401 || res.statusCode == 403 || why.contains('auth')
            ? 'The robot refused the connection ($why). Check the secret key (key icon at the top) '
                'and that the robot is idle and not cleaning.'
            : 'The robot refused the connection ($why).');
      }
      final socket = await res.detachSocket();
      final ws = WebSocket.fromUpgradedSocket(socket, serverSide: false);
      return ManualDrive._(ws, info, client);
    } on ManualDriveException {
      rethrow;
    } on TimeoutException {
      client.close(force: true);
      throw ManualDriveException(
          'No answer from the robot at ${info.ip}:${info.port}. Is your phone on the same Wi-Fi as the robot'
          '${info.ssid != null ? ' ("${info.ssid}")' : ''}?');
    } on SocketException catch (e) {
      client.close(force: true);
      throw ManualDriveException('Could not reach the robot at ${info.ip}:${info.port} (${e.message}). '
          'Is your phone on the same Wi-Fi as the robot?');
    } on HttpException catch (e) {
      client.close(force: true);
      throw ManualDriveException('The robot refused the connection (${e.message}).');
    }
  }

  static final _rnd = Random.secure();

  /// Accepts the key alone, or the whole "serial key" line from the server command.
  static String cleanSecretKey(String input) {
    final parts = input.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.last;
  }

  void send(Object what) {
    if (!isOpen) return;
    final msg = switch (what) {
      DriveCombo c => {'combo': c.wire},
      DriveCommand c => {'command': c.wire},
      _ => throw ArgumentError(what),
    };
    try {
      _ws.add(jsonEncode(msg));
    } catch (_) {
      // connection is closing
    }
  }

  /// Start moving and keep repeating the movement until [stopMoving].
  void startMoving(DriveCombo c) {
    _repeat?.cancel();
    _moving = c;
    send(c);
    _repeat = Timer.periodic(const Duration(milliseconds: 400), (_) => send(c));
  }

  void stopMoving() {
    _repeat?.cancel();
    _repeat = null;
    _moving = null;
    send(DriveCombo.stop);
  }

  Future<void> close() async {
    _repeat?.cancel();
    _keepAlive.cancel();
    send(DriveCombo.stop);
    try {
      await _ws.close(WebSocketStatus.normalClosure).timeout(const Duration(seconds: 2));
    } catch (_) {}
    await _sub.cancel();
    _client.close(force: true);
    _markClosed();
    await _messages.close();
  }
}
