import 'dart:convert';

import 'package:http/http.dart' as http;

import 'phone_tools.dart';

class BrainError implements Exception {
  BrainError(this.spoken, {this.needsKey = false});
  final String spoken;
  final bool needsKey;
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
- Pour réveiller Nathalie ou lui rappeler quelque chose à une heure précise (même téléphone verrouillé, même si l'application est fermée), utilise programmer : à l'heure dite, tu t'ouvres, tu allumes l'écran et tu lui parles. Pour une heure du matin sans date, choisis la prochaine occurrence. Annonce l'heure exacte programmée. Pour reporter un réveil, programme-en un nouveau. Tu peux aussi programmer une action différée (ex. appeler quelqu'un à 8 h).
- Si programmer renvoie un avertissement, appelle demander_acces avec le type ecran_verrouille.
- Ne prétends jamais avoir fait ce que les outils n'ont pas confirmé.
Maintenant : $date (ISO ${n.toIso8601String()}, fuseau ${n.timeZoneName}).''';
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
    _msgs.add({'role': 'user', 'content': text});
    _trim();

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
              'system': _system(),
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
        throw BrainError("Désolée Nathalie, je n'arrive pas à joindre mon cerveau (erreur ${res.statusCode}).");
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final content = (data['content'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _msgs.add({'role': 'assistant', 'content': content});

      if (data['stop_reason'] == 'tool_use') {
        final results = <Map<String, dynamic>>[];
        for (final b in content) {
          if (b['type'] != 'tool_use') continue;
          if (cancelled()) return '';
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
