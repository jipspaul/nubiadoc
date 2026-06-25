# app_secretariat

## Mission

App **secrétariat** Nubia (tablette / desktop), **zéro accès clinique** (`includeClinical: false` —
constante dans `pro_config.dart`). Fonctionnalités : agenda RDV, créneaux bookables, salle d'attente,
liste patients (sans motif ni notes), liste d'attente, devis cabinet, admin membres + secrétariats,
messagerie cabinet. Aucun champ clinique n'est jamais affiché ni enregistré dans le DI.

## Run local

```bash
cd front/apps/app_secretariat
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1
```

## Tests

```bash
# Depuis front/apps/app_secretariat
flutter test

# Suite workspace complète (depuis front/)
dart run melos test
```

## Plan

Avancement FR3.x → issues Forgejo (filtre `[flutter-front] FR3`) + `git log`.

Architecture, règles et commandes → [`front/AGENTS.md`](../../AGENTS.md).
