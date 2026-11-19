# Assistante personnelle — Sarra

Sarra est l'assistante vocale de Nathalie. À l'ouverture, elle apparaît (portrait animé), la salue et lui demande comment l'aider. Toute la conversation est vocale :

- bouton vert **PARLER** en bas au centre → il devient rouge **FIN** ;
- les paroles de Nathalie s'affichent en haut de l'écran ;
- en appuyant sur **FIN**, Sarra répond (ou met fin à la conversation si Nathalie n'a rien dit), puis le bouton redevient **PARLER**.

## Télécharger l'application Android

Le fichier APK est compilé automatiquement par GitHub (onglet **Actions**) et publié dans **Releases**.

Lien de la dernière version : <https://github.com/RymeTVNews/Assistante-personnel/releases/latest/download/Sarra.apk>

Installation : ouvrir le lien sur le téléphone, télécharger `Sarra.apk`, l'ouvrir et autoriser l'installation depuis cette source si Android le demande.

## Ce que Sarra peut faire sur le téléphone

Au premier lancement, Sarra explique puis **demande les accès** un à un (une fenêtre Android s'affiche à chaque fois). Elle peut aussi les redemander plus tard quand une action en a besoin.

| Accès | Ce qu'il permet |
| --- | --- |
| Microphone | entendre Nathalie |
| Calendrier | lire l'agenda du téléphone, ajouter des événements avec rappel |
| Contacts | retrouver un numéro par le nom |
| Téléphone | passer un appel |
| Notifications + écran verrouillé | réveils et rappels qui ouvrent Sarra à l'heure demandée |
| (sans autorisation) | préparer un SMS (Nathalie appuie sur Envoyer), régler un minuteur, ouvrir la navigation, tenir une liste de tâches |

## Alarme dans l'application Horloge

Pour « réveille-moi à 6 h 30 », Sarra règle l'alarme directement dans l'application **Horloge** du téléphone (Samsung, Google, etc.). C'est cette alarme qui sonne à l'heure dite, même téléphone verrouillé, même si Sarra est fermée. Elle peut aussi la répéter certains jours (« tous les jours de semaine »). Android ne confirme pas la création d'une alarme : Sarra propose d'ouvrir la liste des alarmes de l'Horloge pour vérifier, modifier ou supprimer.

## Photo de Sarra

Par défaut, Sarra est un portrait dessiné et animé. Pour utiliser une photo, ajouter un fichier `sarra.jpg` (carré, visage centré) dans `sarra_app/assets/` : l'application le détecte, l'affiche en cercle avec une légère respiration, et un contour qui s'anime quand Sarra écoute (bleu) ou parle (vert). N'utiliser qu'une image dont on a les droits.

## Réveils et rappels, même téléphone verrouillé

Nathalie peut dire par exemple « réveille-moi demain à 6 h 30 » ou « rappelle-moi d'appeler Marie à 14 h ». Sarra programme une alarme exacte sur le téléphone. À l'heure dite, même si l'application est fermée et l'écran verrouillé :

1. le téléphone sonne (son d'alarme) et l'écran s'allume ;
2. Sarra s'ouvre par-dessus l'écran verrouillé et parle à Nathalie ;
3. pour un réveil, Sarra répète toutes les 40 secondes jusqu'à ce que Nathalie appuie sur **PARLER** (elle peut alors dire « patiente 10 minutes ») ;
4. une action prévue (appeler quelqu'un, ouvrir la navigation…) est exécutée à ce moment-là.

Les réveils programmés sont conservés et réarmés après un redémarrage du téléphone. Accès demandés par Sarra pour cela : notifications et ouverture sur écran verrouillé (Android 14 et plus : une page de réglages s'ouvre pour l'activer).

## « Dis Sarra » (écoute en arrière-plan, facultative)

L'icône d'oreille en haut de l'écran (ou la phrase « active l'écoute Dis Sarra ») active un service qui écoute le mot d'éveil. Quand Nathalie dit « Dis Sarra », Sarra s'ouvre, même téléphone verrouillé, répond « Oui Nathalie, je vous écoute » puis écoute la demande ; la demande se termine toute seule après un silence.

- Une **notification reste affichée** tant que l'écoute est active (obligation d'Android), avec un bouton **Arrêter**.
- Accès demandés : micro, notifications, « Afficher par-dessus les autres applications » (sans lui, Sarra ne s'ouvre que par une notification) et exclusion de l'économie de batterie.
- **Vie privée :** quand Android le permet (version 12 et plus, avec le pack de langue français hors ligne), la reconnaissance se fait sur le téléphone. Sinon, c'est le service de reconnaissance vocale de Google qui écoute : l'audio peut alors être envoyé à Google. L'écoute en continu consomme aussi de la batterie.
- Après un redémarrage du téléphone, il faut ouvrir Sarra une fois : Android interdit de relancer un micro en arrière-plan depuis le démarrage.
- Certaines marques (Samsung, Xiaomi, Huawei…) arrêtent les services en arrière-plan : si l'écoute s'interrompt, désactiver l'économie de batterie pour Sarra.
- Limite actuelle : l'écoute est suspendue pendant que Sarra est ouverte à l'écran ; elle reprend dès que Nathalie quitte l'application ou verrouille le téléphone.

Sans « Dis Sarra », Sarra s'ouvre quand un réveil ou un rappel programmé arrive, ou quand Nathalie ouvre l'application.

## Clé d'accès de l'intelligence

Sarra réfléchit avec l'API Claude d'Anthropic. Au premier lancement, l'application demande une clé API (créée sur <https://console.anthropic.com>). Elle est enregistrée uniquement sur le téléphone et n'est jamais dans ce dépôt. Elle peut être modifiée avec l'engrenage en haut de l'écran.

## Contenu du dépôt

- `sarra_app/` — application Android (Flutter). Le projet Android complet est généré à la compilation par `.github/workflows/build-apk.yml`, avec le manifeste et la passerelle calendrier de `sarra_app/android_overrides/`.
- `web-prototype/index.html` — première version web (démonstration), limitée aux fonctions d'une page web.

## Compiler à la main

Sur une machine avec Flutter : `flutter create --platforms=android --org com.sarra --project-name sarra_assistante /tmp/sarra`, puis copier `sarra_app/lib`, `sarra_app/pubspec.yaml` et le contenu de `android_overrides/` aux mêmes emplacements que dans le workflow, et lancer `flutter build apk --release`.
