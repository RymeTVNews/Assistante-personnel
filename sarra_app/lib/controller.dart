import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'alarm_bridge.dart';
import 'brain.dart';
import 'phone_tools.dart';

enum SarraMode { idle, listening, thinking, speaking }

class SarraController extends ChangeNotifier {
  SarraMode mode = SarraMode.idle;
  String said = '';
  String reply = '';
  String note = '';
  VoidCallback? onNeedKey;

  final _stt = SpeechToText();
  final _tts = FlutterTts();
  final _tools = PhoneTools();
  late final Brain _brain = Brain(_tools);
  SharedPreferences? _prefs;
  bool _sttReady = false;
  bool _finishing = false;
  String _locale = 'fr_CA';
  String _accum = '';
  String _live = '';
  int _token = 0;
  bool _waking = false;
  int _wakeGen = 0;
  bool wakeOn = false;
  bool _handsFree = false;
  Timer? _silenceTimer;

  // ---------- démarrage ----------

  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
    _brain.apiKey = _prefs!.getString('apiKey');
    await _initTts();

    // Sarra a été ouverte par un réveil ou un rappel (même écran verrouillé) : elle parle tout de suite.
    AlarmBridge.init();
    AlarmBridge.onWake = (w) => _handleWake(w);
    await _syncWake();
    final wake = await AlarmBridge.takeWake();
    if (wake != null) {
      await _handleWake(wake);
      return;
    }

    final firstRun = !(_prefs!.getBool('onboarded2') ?? false);
    final hour = DateTime.now().hour;
    await _say('${hour >= 18 ? 'Bonsoir' : 'Bonjour'} Nathalie, je suis Sarra. '
        "Comment puis-je vous aider dans l'organisation de votre journée ?");
    if (firstRun) {
      await _onboarding();
      await _prefs!.setBool('onboarded2', true);
    }
    if ((_brain.apiKey ?? '').isEmpty) onNeedKey?.call();
  }

  Future<void> _initTts() async {
    try {
      final ok = await _tts.isLanguageAvailable('fr-CA');
      await _tts.setLanguage(ok == true ? 'fr-CA' : 'fr-FR');
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.05);
    } catch (_) {}
  }

  /// Sarra explique, puis demande à Nathalie les accès dont elle a besoin.
  Future<void> _onboarding() async {
    await _say("Pour vous aider pleinement, j'ai besoin de quelques autorisations. "
        "Je les demande une à une : acceptez-les à l'écran.");
    final steps = <(String, Permission)>[
      ('Le microphone, pour vous entendre.', Permission.microphone),
      ('Le calendrier, pour gérer votre agenda.', Permission.calendarFullAccess),
      ('Les contacts, pour retrouver vos proches.', Permission.contacts),
      ('Le téléphone, pour passer vos appels.', Permission.phone),
    ];
    for (final s in steps) {
      await _say(s.$1);
      try {
        await s.$2.request();
      } catch (_) {}
    }
    await _say("Les notifications, pour pouvoir vous réveiller à l'heure demandée.");
    try {
      await Permission.notification.request();
    } catch (_) {}
    try {
      if (!await AlarmBridge.fullScreenOk()) {
        await _say("Et l'ouverture sur écran verrouillé : je vous ouvre la page, activez l'option pour Sarra.");
        await AlarmBridge.openFullScreenSettings();
      }
    } catch (_) {}
    await _say('Merci. Appuyez sur PARLER et dites-moi ce dont vous avez besoin.');
  }

  // ---------- réveils et rappels ----------

  /// À l'heure programmée : Sarra parle, exécute l'action prévue, et répète le réveil jusqu'à ce que Nathalie réponde.
  Future<void> _handleWake(Map<String, dynamic> w) async {
    // « Dis Sarra » : elle répond, puis écoute Nathalie sans qu'elle ait à toucher l'écran.
    if ('${w['kind']}' == 'ecoute') {
      _wakeGen++;
      _waking = false;
      _handsFree = true;
      await _say('Oui Nathalie, je vous écoute.');
      await onTalk();
      return;
    }
    final gen = ++_wakeGen;
    _waking = true;
    final kind = '${w['kind']}';
    final label = '${w['label'] ?? ''}'.trim();
    final payload = '${w['payload'] ?? ''}';
    final n = DateTime.now();
    final heure = '${n.hour} h ${n.minute.toString().padLeft(2, '0')}';
    note = kind == 'reveil' ? 'Réveil : appuyez sur PARLER pour m’arrêter.' : '';
    notifyListeners();

    final text = kind == 'reveil'
        ? "Bonjour Nathalie, il est $heure. C'est l'heure de vous réveiller."
            '${label.isNotEmpty ? ' $label.' : ''} Appuyez sur PARLER pour m’arrêter ou me demander de patienter.'
        : 'Nathalie, un rappel : ${label.isEmpty ? 'c’est l’heure' : label}.';

    await _say(text);

    if (payload.isNotEmpty) {
      try {
        final p = jsonDecode(payload) as Map;
        await _tools.run('${p['outil']}', Map<String, dynamic>.from((p['arguments'] ?? {}) as Map));
      } catch (e) {
        note = "L'action prévue n'a pas pu être exécutée.";
        notifyListeners();
      }
    }

    if (kind == 'reveil') {
      for (var i = 0; i < 10 && _waking && gen == _wakeGen; i++) {
        for (var s = 0; s < 40 && _waking && gen == _wakeGen; s++) {
          await Future.delayed(const Duration(seconds: 1));
        }
        if (_waking && gen == _wakeGen) await _say(text);
      }
    }
    if (gen == _wakeGen) {
      _waking = false;
      try {
        await AlarmBridge.stopSound();
      } catch (_) {}
    }
  }

  // ---------- écoute « Dis Sarra » ----------

  Future<void> _syncWake() async {
    try {
      wakeOn = await AlarmBridge.wakeEnabled();
      if (wakeOn) await AlarmBridge.wakeStart();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> toggleWake() async {
    final target = !wakeOn;
    try {
      final r = await _tools.run('ecoute_continue', {'actif': target}) as Map;
      wakeOn = target;
      final warn = r['avertissements'];
      note = warn is List && warn.isNotEmpty ? '${warn.first}' : '';
    } catch (e) {
      note = e.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  // ---------- clé d'accès ----------

  Future<String?> loadKey() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!.getString('apiKey');
  }

  Future<void> saveKey(String key) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('apiKey', key);
    _brain.apiKey = key;
    note = '';
    notifyListeners();
  }

  // ---------- voix de Sarra ----------

  Future<void> _say(String text) async {
    final my = ++_token;
    reply = text;
    mode = SarraMode.speaking;
    notifyListeners();
    try {
      await _tts.speak(text);
    } catch (_) {}
    if (my == _token && mode == SarraMode.speaking) {
      mode = SarraMode.idle;
      notifyListeners();
    }
  }

  // ---------- bouton PARLER / FIN ----------

  Future<void> onTalk() async {
    if (_waking) {
      _waking = false;
      try {
        await AlarmBridge.stopSound();
      } catch (_) {}
    }
    if (mode == SarraMode.listening) return _finish();
    _token++;
    try {
      await _tts.stop();
    } catch (_) {}
    note = '';
    if (!await _ensureMic()) {
      mode = SarraMode.idle;
      notifyListeners();
      return;
    }
    said = '';
    _accum = '';
    _live = '';
    mode = SarraMode.listening;
    notifyListeners();
    if (_handsFree) _armSilence(const Duration(seconds: 12));
    await _listen();
  }

  Future<bool> _ensureMic() async {
    var s = await Permission.microphone.status;
    if (!s.isGranted) s = await Permission.microphone.request();
    if (s.isPermanentlyDenied) {
      note = 'Le micro est bloqué : autorisez-le dans les réglages.';
      notifyListeners();
      await openAppSettings();
      return false;
    }
    if (!s.isGranted) {
      note = "Sans le micro, je ne peux pas vous entendre.";
      notifyListeners();
      return false;
    }
    if (!_sttReady) {
      _sttReady = await _stt.initialize(onError: _onSttError, onStatus: _onSttStatus);
      if (!_sttReady) {
        note = 'La reconnaissance vocale est indisponible sur ce téléphone.';
        notifyListeners();
        return false;
      }
      final locales = await _stt.locales();
      String norm(String s) => s.toLowerCase().replaceAll('-', '_');
      final ca = locales.where((l) => norm(l.localeId) == 'fr_ca');
      final fr = locales.where((l) => norm(l.localeId).startsWith('fr'));
      if (ca.isNotEmpty) {
        _locale = ca.first.localeId;
      } else if (fr.isNotEmpty) {
        _locale = fr.first.localeId;
      }
    }
    return true;
  }

  Future<void> _listen() async {
    await _stt.listen(
      onResult: _onResult,
      localeId: _locale,
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 20),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      ),
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    if (mode != SarraMode.listening && !_finishing) return;
    if (r.finalResult) {
      _accum = '$_accum ${r.recognizedWords}'.trim();
      _live = '';
    } else {
      _live = r.recognizedWords;
    }
    said = '$_accum $_live'.trim();
    notifyListeners();
    if (_handsFree) _armSilence(const Duration(milliseconds: 2500));
  }

  /// Mains libres (après « Dis Sarra ») : la demande se termine toute seule après un silence.
  void _armSilence(Duration d) {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(d, () {
      if (mode == SarraMode.listening && _handsFree) _finish();
    });
  }

  void _restartListening() {
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mode == SarraMode.listening && !_stt.isListening) {
        if (_live.isNotEmpty) {
          _accum = '$_accum $_live'.trim();
          _live = '';
        }
        _listen();
      }
    });
  }

  void _onSttStatus(String s) {
    if ((s == 'done' || s == 'notListening') && mode == SarraMode.listening) _restartListening();
  }

  void _onSttError(SpeechRecognitionError e) {
    if (mode != SarraMode.listening) return;
    if (e.permanent) {
      mode = SarraMode.idle;
      note = 'Le micro ne répond pas (${e.errorMsg}).';
      notifyListeners();
    } else {
      _restartListening();
    }
  }

  Future<void> _finish() async {
    if (mode != SarraMode.listening) return;
    final gen = ++_token;
    _silenceTimer?.cancel();
    _handsFree = false;
    _finishing = true;
    mode = SarraMode.thinking;
    notifyListeners();
    try {
      await _stt.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 600));
    _finishing = false;
    if (gen != _token) return;
    final text = '$_accum $_live'.trim();
    _accum = '';
    _live = '';
    if (text.isEmpty) {
      _brain.reset();
      said = '';
      notifyListeners();
      await _say("D'accord Nathalie, à bientôt. Appuyez sur PARLER quand vous aurez besoin de moi.");
      return;
    }
    await _ask(text);
  }

  Future<void> _ask(String text) async {
    said = text;
    mode = SarraMode.thinking;
    notifyListeners();
    final my = ++_token;
    String answer;
    try {
      answer = await _brain.ask(text, cancelled: () => my != _token);
    } on BrainError catch (e) {
      answer = e.spoken;
      if (e.needsKey) Future.microtask(() => onNeedKey?.call());
    } on SocketException {
      answer = "Je n'ai pas de connexion internet pour le moment.";
    } on TimeoutException {
      answer = "Je mets trop de temps à réfléchir, pouvez-vous répéter ?";
    } catch (_) {
      answer = 'Désolée Nathalie, une erreur est survenue. Pouvez-vous répéter ?';
    }
    if (my != _token) return;
    await _say(answer.isEmpty ? "Je n'ai pas bien compris, pouvez-vous reformuler ?" : answer);
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.cancel();
    super.dispose();
  }
}
