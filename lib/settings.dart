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
        _cleaning = data[_kCleaning] is Map
            ? CleaningPrefs.fromJson((data[_kCleaning] as Map).cast<String, dynamic>())
            // older versions only stored the suction modes
            : CleaningPrefs.fromJson({
                if (data['gen3mode'] is int) 'gen3Mode': data['gen3mode'],
                if (data['gen4mode'] is String) 'gen4Mode': data['gen4mode'],
              }),
        _notifications = (data[_kNotify] as bool?) ?? false,
        _manualKeys = {
          if (data[_kManualKeys] is Map)
            for (final e in (data[_kManualKeys] as Map).entries)
              if (e.key is String && e.value is String) e.key as String: e.value as String,
        };

  static const _kServer = 'server';
  static const _kCleaning = 'cleaning';
  static const _kManualKeys = 'manualKeys';
  static const _kNotify = 'notifications';

  /// Fast serveradress som byggs in i appen, t.ex.
  ///   flutter run --release --dart-define=VACUULA_SERVER=192.168.1.250
  /// Används när inget annat har sparats i appen.
  static final String _defaultServer = VacuulaApi.normalizeUrl(
      const String.fromEnvironment('VACUULA_SERVER'));

  final File? _file;
  String _server;
  CleaningPrefs _cleaning;
  final Map<String, String> _manualKeys;
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
  bool get notifications => _notifications;
  bool get hasServer => _server.isNotEmpty;

  /// How cleanings are started (area, suction, navigation…).
  CleaningPrefs get cleaning => _cleaning;

  /// Saves server and notification settings and tells listeners (the app reconnects).
  Future<void> save({
    required String server,
    required bool notifications,
  }) async {
    _server = VacuulaApi.normalizeUrl(server);
    _notifications = notifications;
    notifyListeners();
    await _write();
  }

  /// Gen3 robot secret key for remote control (manual driving), per serial.
  String? manualKey(String serial) => _manualKeys[serial];

  Future<void> setManualKey(String serial, String? key) async {
    if (key == null || key.trim().isEmpty) {
      _manualKeys.remove(serial);
    } else {
      _manualKeys[serial] = key.trim();
    }
    await _write();
  }

  /// Saves the cleaning choices. Does not notify listeners (no reconnect needed).
  Future<void> setCleaning(CleaningPrefs p) async {
    _cleaning = p;
    await _write();
  }

  Future<void> _write() async {
    final file = _file;
    if (file == null) return;
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        _kServer: _server,
        _kCleaning: _cleaning.toJson(),
        _kManualKeys: _manualKeys,
        _kNotify: _notifications,
      }), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Kunde inte spara – inställningen gäller ändå tills appen stängs.
    }
  }
}
