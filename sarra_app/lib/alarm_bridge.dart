import 'package:flutter/services.dart';

/// Pont vers les réveils et rappels natifs (alarme exacte, ouverture sur écran verrouillé).
class AlarmBridge {
  static const _ch = MethodChannel('sarra/alarm');
  static void Function(Map<String, dynamic>)? onWake;
  static bool _init = false;

  static void init() {
    if (_init) return;
    _init = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'wake') {
        onWake?.call(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }

  static Future<int> schedule(DateTime when, String label, String kind, String? payload) async {
    final id = await _ch.invokeMethod<int>('schedule', {
      'time': when.millisecondsSinceEpoch,
      'label': label,
      'kind': kind,
      'payload': payload,
    });
    return id ?? 0;
  }

  static Future<void> cancel(int id) => _ch.invokeMethod('cancel', {'id': id});

  static Future<List<Map<String, dynamic>>> list() async {
    final raw = await _ch.invokeMethod<List<dynamic>>('list');
    return (raw ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Appelé au démarrage : renvoie le réveil qui vient d'ouvrir l'application, s'il y en a un.
  static Future<Map<String, dynamic>?> takeWake() async {
    final raw = await _ch.invokeMethod<Map<dynamic, dynamic>>('takeWake');
    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  static Future<void> stopSound() => _ch.invokeMethod('stopSound');

  static Future<bool> fullScreenOk() async => (await _ch.invokeMethod<bool>('fullScreenOk')) ?? true;

  static Future<void> openFullScreenSettings() => _ch.invokeMethod('openFullScreenSettings');
}
