import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api.dart';

/// Appens inställningar, sparade som en liten JSON-fil på telefonen.
///
/// Använder bara dart:io (inga plugins), så det finns inget som kan krångla
/// i Android-release-byggen.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._file, Map<String, dynamic> data)
      : _server = (data[_kServer] as String?) ?? _defaultServer,
        _gen3Mode = (data[_kGen3] as int?) ?? 2,
        _gen4Mode = (data[_kGen4] as String?) ?? 'auto',
        _notifications = (data[_kNotify] as bool?) ?? false;

  static const _kServer = 'server';
  static const _kGen3 = 'gen3mode';
  static const _kGen4 = 'gen4mode';
  static const _kNotify = 'notifications';

  /// Fast serveradress som byggs in i appen, t.ex.
  ///   flutter run --release --dart-define=VACUULA_SERVER=192.168.1.250
  /// Används när inget annat har sparats i appen.
  static final String _defaultServer = VacuulaApi.normalizeUrl(
      const String.fromEnvironment('VACUULA_SERVER'));

  final File? _file;
  String _server;
  int _gen3Mode;
  String _gen4Mode;
  bool _notifications;

  /// Appens egen, privata mapp.
  /// Android: `/data/user/0/<app>/files` (systemTemp är appens cache-mapp)
  /// iOS: `<app-container>/Library/Application Support`
  static Directory? _settingsDir() {
    try {
      if (Platform.isIOS) {
        final home = Platform.environment['HOME'];
        if (home != null) return Directory('$home/Library/Application Support');
      }
      return Directory('${Directory.systemTemp.parent.path}/files');
    } catch (_) {
      return null;
    }
  }

  static Future<AppSettings> load() async {
    File? file;
    var data = <String, dynamic>{};
    try {
      final dir = _settingsDir();
      if (dir != null) {
        await dir.create(recursive: true);
        file = File('${dir.path}/vacuula_settings.json');
        if (await file.exists()) {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) data = decoded;
        }
      }
    } catch (_) {
      // Trasig eller oläsbar fil – börja med standardvärden.
    }
    return AppSettings._(file, data);
  }

  String get server => _server;
  int get gen3Mode => _gen3Mode;
  String get gen4Mode => _gen4Mode;
  bool get notifications => _notifications;
  bool get hasServer => _server.isNotEmpty;

  CleaningPrefs get cleaning =>
      CleaningPrefs(gen3Mode: _gen3Mode, gen4Mode: _gen4Mode);

  Future<void> save({
    required String server,
    required int gen3Mode,
    required String gen4Mode,
    required bool notifications,
  }) async {
    _server = VacuulaApi.normalizeUrl(server);
    _gen3Mode = gen3Mode;
    _gen4Mode = gen4Mode;
    _notifications = notifications;
    notifyListeners();
    final file = _file;
    if (file == null) return;
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        _kServer: _server,
        _kGen3: _gen3Mode,
        _kGen4: _gen4Mode,
        _kNotify: _notifications,
      }), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Kunde inte spara – inställningen gäller ändå tills appen stängs.
    }
  }
}
