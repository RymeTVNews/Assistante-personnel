import 'dart:convert';

import 'package:http/http.dart' as http;

import 'phone_tools.dart';

class BrainError implements Exception {
  BrainError(this.spoken, {this.needsKey = false, this.detail});
  final String spoken;
  final bool needsKey;

  /// Message technique du service, affiché en bas de l'écran (jamais lu à voix haute).
  final String? detail;
}

/// Le « cerveau » de Sarra : l'API Claude d'Anthropic, avec les actions du téléphone comme outils.
class Brain {
  Brain(this.tools);

  final PhoneTools tools;
  String? apiKey;
  static const model = 'claude-haiku-5-5';
  final List<Map<String, dynamic>> _msgs = [];

  void reset() => _msgs.clear();

  static const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  static const _mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];

  String _system() {
    final n = DateTime.now();
    final date = '${_jours[n.weekday - 1]} ${n.day} ${_mois[n.month - 1]} ${n.year}, '
        '${n.hour} h ${n.minute.toString().padLeft(2, '0')}';
    return '''Tu es Sarra, l'assistante vocale personnelle de Nathalie. Tu l'aides à organiser ses journées et tu agis sur son téléphone grâce à tes outils : calendrier, contacts, appels, messages, alarmes, minuteurs, navigation, tâches.
Règles :
- Tes réponses sont lues à voix haute : 1 à 3 phrases courtes, sans markdown, sans liste, sans émoji. Dis les heures comme "14 h 30". Tu vouvoies Nathalie, avec chaleur et efficacité.
- Utilise les outils pour agir et pour lire l'agenda au lieu de supposer, puis confirme brièvement ce que tu as fait.
- Si une demande est ambiguë, pose une seule question courte. Si plusieurs contacts correspondent, demande lequel.
- Pour un SMS, tu prépares le message : Nathalie doit appuyer elle-même sur Envoyer, dis-le.
- Si un accès du téléphone est refusé, explique-le simplement. Tu peux utiliser demander_acces pour redemander une autorisation.
- Pour réveiller Nathalie à une heure précise, utilise alarme_horloge : l'alarme est réglée dans l'application Horloge du téléphone et sonne à l'heure dite, même téléphone verrouillé et même si tu es fermée. Annonce l'heure exacte. Android ne confirme pas la création : dis que tu as demandé à l'Horloge, et propose d'ouvrir la liste des alarmes (alarmes_afficher) pour vérifier ou supprimer. Pour reporter un réveil, règles-en un nouveau.
- Pour qu'une voix de Sarra parle à une heure précise (rappel) ou pour exécuter une action différée (ex. appeler quelqu'un à 8 h), utilise programmer : à l'heure dite, tu t'ouvres, tu allumes l'écran et tu agis. Si Nathalie veut à la fois la sonnerie et ta voix pour se réveiller, fais les deux.
- Nathalie peut activer ou arrêter l'écoute du mot d'éveil « Dis Sarra » (tu t'ouvres quand elle le prononce, même téléphone verrouillé) : utilise ecoute_continue. Précise qu'une notification reste affichée tant que l'écoute est active.
- Si programmer renvoie un avertissement, appelle demander_acces avec le type ecran_verrouille.
- Ne prétends jamais avoir fait ce que les outils n'ont pas confirmé.
Maintenant : $date (ISO ${n.toIso8601String()}, fuseau ${n.timeZoneName}).''';
  }

  /// Les réflexions des demandes précédentes sont liées à un ancien texte de réglage : on les retire.
  void _dropThinking() {
    for (final m in _msgs) {
      if (m['role'] == 'assistant' && m['content'] is List) {
        m['content'] = (m['content'] as List)
            .where((b) => b is Map && b['type'] != 'thinking' && b['type'] != 'redacted_thinking')
            .toList();
      }
    }
    _msgs.removeWhere((m) => m['role'] == 'assistant' && m['content'] is List && (m['content'] as List).isEmpty);
  }

  void _trim() {
    while (_msgs.length > 24 ||
        (_msgs.isNotEmpty && !(_msgs.first['role'] == 'user' && _msgs.first['content'] is String))) {
      if (_msgs.isEmpty) break;
      _msgs.removeAt(0);
    }
  }

  Future<String> ask(String text, {required bool Function() cancelled}) async {
    final key = apiKey;
    if (key == null || key.isEmpty) {
      throw BrainError(
          "Il me manque ma clé d'accès pour réfléchir. Touchez l'engrenage en haut de l'écran pour la saisir.",
          needsKey: true);
    }
    _dropThinking();
    _msgs.add({'role': 'user', 'content': text});
    _trim();

    // Le texte de réglage doit rester identique pendant toute la demande : le service lie ses
    // « réflexions » à ce texte et refuse de les relire si l'heure qu'il contient a changé.
    final system = _system();

    for (var i = 0; i < 8; i++) {
      final res = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 500,
              'system': system,
              'tools': tools.definitions,
              'messages': _msgs,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (res.statusCode == 401 || res.statusCode == 403) {
        throw BrainError("Ma clé d'accès est refusée. Touchez l'engrenage pour la corriger.", needsKey: true);
      }
      if (res.statusCode == 429) {
        throw BrainError('Je suis un peu débordée, réessayez dans un instant.');
      }
      if (res.statusCode != 200) {
        var msg = '';
        try {
          msg = '${(jsonDecode(utf8.decode(res.bodyBytes)) as Map)['error']['message']}';
        } catch (_) {}
        // Une conversation abîmée ferait échouer toutes les demandes suivantes : on repart de zéro.
        _msgs.clear();
        throw BrainError(
          "Désolée Nathalie, le service a refusé ma demande (erreur ${res.statusCode}). Le détail est affiché en bas de l'écran.",
          detail: 'Erreur ${res.statusCode} : ${msg.isEmpty ? 'sans détail' : msg}',
        );
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      // Le service refuse les blocs de texte vides quand on les lui renvoie : on les écarte.
      final content = (data['content'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((b) => !(b['type'] == 'text' && ('${b['text'] ?? ''}').trim().isEmpty))
          .toList();
      if (content.isEmpty) return '';
      _msgs.add({'role': 'assistant', 'content': content});

      if (data['stop_reason'] == 'tool_use') {
        final results = <Map<String, dynamic>>[];
        for (final b in content) {
          if (b['type'] != 'tool_use') continue;
          if (cancelled()) {
            _msgs.removeLast(); // évite un appel d'outil sans résultat, qui ferait échouer la suite
            return '';
          }
          String out;
          var isError = false;
          try {
            out = jsonEncode(await tools.run(b['name'] as String, Map<String, dynamic>.from(b['input'] as Map)));
          } catch (e) {
            out = 'Erreur : ${e.toString().replaceFirst('Exception: ', '')}';
            isError = true;
          }
          results.add({'type': 'tool_result', 'tool_use_id': b['id'], 'content': out, 'is_error': isError});
        }
        _msgs.add({'role': 'user', 'content': results});
        continue;
      }

      return content
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String)
          .join(' ')
          .replaceAll(RegExp(r'[*#_`>]'), '')
          .trim();
    }
    return "Je n'arrive pas à terminer cette demande, pouvez-vous la reformuler ?";
  }
}
