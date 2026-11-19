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
| (sans autorisation) | préparer un SMS (Nathalie appuie sur Envoyer), régler une alarme ou un minuteur, ouvrir la navigation, tenir une liste de tâches |

## Clé d'accès de l'intelligence

Sarra réfléchit avec l'API Claude d'Anthropic. Au premier lancement, l'application demande une clé API (créée sur <https://console.anthropic.com>). Elle est enregistrée uniquement sur le téléphone et n'est jamais dans ce dépôt. Elle peut être modifiée avec l'engrenage en haut de l'écran.

## Contenu du dépôt

- `sarra_app/` — application Android (Flutter). Le projet Android complet est généré à la compilation par `.github/workflows/build-apk.yml`, avec le manifeste et la passerelle calendrier de `sarra_app/android_overrides/`.
- `web-prototype/index.html` — première version web (démonstration), limitée aux fonctions d'une page web.

## Compiler à la main

Sur une machine avec Flutter : `flutter create --platforms=android --org com.sarra --project-name sarra_assistante /tmp/sarra`, puis copier `sarra_app/lib`, `sarra_app/pubspec.yaml` et le contenu de `android_overrides/` aux mêmes emplacements que dans le workflow, et lancer `flutter build apk --release`.
