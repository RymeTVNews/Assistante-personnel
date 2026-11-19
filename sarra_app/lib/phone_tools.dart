import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les actions que Sarra peut exécuter sur le téléphone de Nathalie.
/// Chaque action demande elle-même l'accès Android dont elle a besoin.
class PhoneTools {
  static const _cal = MethodChannel('sarra/calendar');

  static Map<String, dynamic> _def(String name, String description,
      Map<String, dynamic> props, [List<String> required = const []]) {
    return {
      'name': name,
      'description': description,
      'input_schema': {'type': 'object', 'properties': props, 'required': required},
    };
  }

  static const _s = {'type': 'string'};
  static const _n = {'type': 'number'};

  final List<Map<String, dynamic>> definitions = [
    _def('heure_actuelle', "Donne la date et l'heure actuelles du téléphone.", {}),
    _def(
        'demander_acces',
        "Demande à Nathalie d'autoriser un accès du téléphone (une fenêtre Android s'affiche). type : microphone, calendrier, contacts ou telephone.",
        {'type': _s},
        ['type']),
    _def(
        'agenda_lire',
        "Lit les événements du calendrier du téléphone entre deux moments (format ISO 8601 local, ex. 2026-11-19T00:00:00). Sans arguments : aujourd'hui.",
        {'debut': _s, 'fin': _s}),
    _def(
        'agenda_ajouter',
        "Ajoute un événement au calendrier du téléphone, avec un rappel 10 minutes avant. debut et fin au format ISO 8601 local. Sans fin : durée d'une heure.",
        {'titre': _s, 'debut': _s, 'fin': _s, 'lieu': _s, 'notes': _s},
        ['titre', 'debut']),
    _def('contacts_chercher', "Cherche un contact par son nom et donne ses numéros de téléphone.", {'nom': _s}, ['nom']),
    _def(
        'appeler',
        "Lance un appel téléphonique. Donne soit numero, soit nom (contact). Si plusieurs contacts correspondent, rien n'est appelé et la liste est renvoyée.",
        {'numero': _s, 'nom': _s}),
    _def(
        'sms_preparer',
        "Ouvre l'application de messages avec le texte déjà écrit. Nathalie doit appuyer elle-même sur Envoyer. Donne soit numero, soit nom (contact).",
        {'numero': _s, 'nom': _s, 'message': _s},
        ['message']),
    _def('alarme', "Règle une alarme du téléphone à une heure précise (heure 0-23, minute 0-59).",
        {'heure': _n, 'minute': _n, 'libelle': _s}, ['heure', 'minute']),
    _def('minuteur', "Lance un minuteur du téléphone (durée en secondes).", {'secondes': _n, 'libelle': _s}, ['secondes']),
    _def('navigation', "Ouvre l'application de cartes sur une destination.", {'destination': _s}, ['destination']),
    _def('taches_lire', "Liste les tâches non terminées de Nathalie.", {}),
    _def('tache_ajouter', "Ajoute une tâche à la liste de Nathalie.", {'titre': _s, 'echeance': _s}, ['titre']),
    _def('tache_terminer', "Marque une tâche comme terminée par son identifiant.", {'id': _n}, ['id']),
  ];

  Future<dynamic> run(String name, Map<String, dynamic> a) async {
    switch (name) {
      case 'heure_actuelle':
        final n = DateTime.now();
        return {'maintenant': n.toIso8601String(), 'fuseau': n.timeZoneName};
      case 'demander_acces':
        return _demanderAcces('${a['type']}');
      case 'agenda_lire':
        return _agendaLire(a);
      case 'agenda_ajouter':
        return _agendaAjouter(a);
      case 'contacts_chercher':
        return _contactsChercher('${a['nom']}');
      case 'appeler':
        return _appeler(a);
      case 'sms_preparer':
        return _smsPreparer(a);
      case 'alarme':
        return _alarme(a);
      case 'minuteur':
        return _minuteur(a);
      case 'navigation':
        await AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: 'geo:0,0?q=${Uri.encodeComponent('${a['destination']}')}',
        ).launch();
        return {'ok': true};
      case 'taches_lire':
        return (await _taches()).where((t) => t['fait'] != true).toList();
      case 'tache_ajouter':
        return _tacheAjouter(a);
      case 'tache_terminer':
        return _tacheTerminer(a);
      default:
        throw Exception('Action inconnue : $name');
    }
  }

  // ---------- accès Android ----------

  Future<void> need(Permission p, String label) async {
    var s = await p.status;
    if (s.isGranted) return;
    s = await p.request();
    if (s.isGranted) return;
    if (s.isPermanentlyDenied) {
      await openAppSettings();
      throw Exception("L'accès $label est bloqué. J'ai ouvert les réglages : Nathalie doit l'autoriser, puis redemander.");
    }
    throw Exception("Nathalie a refusé l'accès $label.");
  }

  Future<Map<String, dynamic>> _demanderAcces(String type) async {
    switch (type.toLowerCase()) {
      case 'microphone':
        await need(Permission.microphone, 'au microphone');
        break;
      case 'calendrier':
        await need(Permission.calendarFullAccess, 'au calendrier');
        break;
      case 'contacts':
        await need(Permission.contacts, 'aux contacts');
        break;
      case 'telephone':
        await need(Permission.phone, 'au téléphone');
        break;
      default:
        throw Exception('Type inconnu : $type');
    }
    return {'accorde': true, 'type': type};
  }

  // ---------- calendrier ----------

  DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse('$v');

  Future<dynamic> _agendaLire(Map<String, dynamic> a) async {
    await need(Permission.calendarFullAccess, 'au calendrier');
    final now = DateTime.now();
    final start = _dt(a['debut']) ?? DateTime(now.year, now.month, now.day);
    final end = _dt(a['fin']) ?? start.add(const Duration(days: 1));
    final raw = await _cal.invokeMethod<List<dynamic>>('query', {
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
    return (raw ?? []).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return {
        'titre': m['title'],
        'debut': DateTime.fromMillisecondsSinceEpoch(m['begin'] as int).toIso8601String(),
        'fin': DateTime.fromMillisecondsSinceEpoch(m['end'] as int).toIso8601String(),
        'lieu': m['location'],
        'toute_la_journee': m['allDay'],
      };
    }).toList();
  }

  Future<dynamic> _agendaAjouter(Map<String, dynamic> a) async {
    await need(Permission.calendarFullAccess, 'au calendrier');
    final start = _dt(a['debut']);
    if (start == null) throw Exception('Date de début invalide');
    final end = _dt(a['fin']) ?? start.add(const Duration(hours: 1));
    final id = await _cal.invokeMethod<int>('insert', {
      'title': '${a['titre']}',
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'location': a['lieu'],
      'notes': a['notes'],
    });
    return {'ok': true, 'id': id};
  }

  // ---------- contacts, appels, messages ----------

  String _norm(String s) {
    const from = 'àâäçéèêëîïôöùûüÿ';
    const to = 'aaaceeeeiioouuuy';
    var out = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _trouverContacts(String nom) async {
    await need(Permission.contacts, 'aux contacts');
    final all = await FlutterContacts.getContacts(withProperties: true);
    final q = _norm(nom);
    return all
        .where((c) => _norm(c.displayName).contains(q))
        .take(5)
        .map((c) => {'nom': c.displayName, 'numeros': c.phones.map((p) => p.number).toList()})
        .toList();
  }

  Future<dynamic> _contactsChercher(String nom) => _trouverContacts(nom);

  /// Renvoie un numéro, ou lève une erreur lisible si le contact est introuvable ou ambigu.
  Future<String> _numero(Map<String, dynamic> a) async {
    final direct = a['numero'];
    if (direct != null && '$direct'.trim().isNotEmpty) return '$direct'.replaceAll(RegExp(r'[^0-9+]'), '');
    final nom = a['nom'];
    if (nom == null || '$nom'.trim().isEmpty) throw Exception('Il faut un nom ou un numéro.');
    final found = (await _trouverContacts('$nom')).where((c) => (c['numeros'] as List).isNotEmpty).toList();
    if (found.isEmpty) throw Exception('Aucun contact avec un numéro ne correspond à « $nom ».');
    final numbers = <String>{for (final c in found) for (final n in c['numeros'] as List) '$n'.replaceAll(RegExp(r'[^0-9+]'), '')};
    if (found.length > 1 || numbers.length > 1) {
      throw Exception('Plusieurs possibilités, demande laquelle à Nathalie : ${jsonEncode(found)}');
    }
    return numbers.first;
  }

  Future<dynamic> _appeler(Map<String, dynamic> a) async {
    final n = await _numero(a);
    await need(Permission.phone, 'au téléphone');
    await AndroidIntent(action: 'android.intent.action.CALL', data: 'tel:$n').launch();
    return {'ok': true, 'appel_vers': n};
  }

  Future<dynamic> _smsPreparer(Map<String, dynamic> a) async {
    final n = await _numero(a);
    await AndroidIntent(
      action: 'android.intent.action.SENDTO',
      data: 'smsto:$n',
      arguments: {'sms_body': '${a['message']}'},
    ).launch();
    return {'ok': true, 'note': "Le message est prêt, Nathalie doit appuyer sur Envoyer.", 'vers': n};
  }

  // ---------- alarmes et minuteurs ----------

  Future<dynamic> _alarme(Map<String, dynamic> a) async {
    final h = (a['heure'] as num).toInt(), m = (a['minute'] as num).toInt();
    if (h < 0 || h > 23 || m < 0 || m > 59) throw Exception('Heure invalide');
    await AndroidIntent(action: 'android.intent.action.SET_ALARM', arguments: {
      'android.intent.extra.alarm.HOUR': h,
      'android.intent.extra.alarm.MINUTES': m,
      'android.intent.extra.alarm.MESSAGE': '${a['libelle'] ?? 'Sarra'}',
      'android.intent.extra.alarm.SKIP_UI': true,
    }).launch();
    return {'ok': true, 'alarme': '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}'};
  }

  Future<dynamic> _minuteur(Map<String, dynamic> a) async {
    final s = (a['secondes'] as num).toInt();
    if (s < 1 || s > 86400) throw Exception('Durée invalide');
    await AndroidIntent(action: 'android.intent.action.SET_TIMER', arguments: {
      'android.intent.extra.alarm.LENGTH': s,
      'android.intent.extra.alarm.MESSAGE': '${a['libelle'] ?? 'Sarra'}',
      'android.intent.extra.alarm.SKIP_UI': true,
    }).launch();
    return {'ok': true, 'secondes': s};
  }

  // ---------- tâches (stockées sur le téléphone) ----------

  Future<List<Map<String, dynamic>>> _taches() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('taches');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _saveTaches(List<Map<String, dynamic>> t) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('taches', jsonEncode(t));
  }

  Future<dynamic> _tacheAjouter(Map<String, dynamic> a) async {
    final t = await _taches();
    final id = t.isEmpty ? 1 : (t.map((e) => e['id'] as int).reduce((x, y) => x > y ? x : y) + 1);
    t.add({'id': id, 'titre': '${a['titre']}', 'echeance': a['echeance'] ?? '', 'fait': false});
    await _saveTaches(t);
    return {'ok': true, 'id': id};
  }

  Future<dynamic> _tacheTerminer(Map<String, dynamic> a) async {
    final t = await _taches();
    final id = (a['id'] as num).toInt();
    final i = t.indexWhere((e) => e['id'] == id);
    if (i < 0) return {'ok': false};
    t[i]['fait'] = true;
    await _saveTaches(t);
    return {'ok': true};
  }
}
