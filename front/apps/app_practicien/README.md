# app_practicien

## Mission

App **praticien** Nubia (tablette / desktop), accès clinique complet (`includeClinical: true`).
Fonctionnalités : tableau de bord cabinet, agenda semaine, liste patients + fiche, consultation
clinique CCAM (gated), ordonnances (gated), messagerie cabinet, salle d'attente. Les destinations
marquées `requiresClinical` sont masquées si `session.canAccessClinical` est faux.

## Run local

```bash
cd front/apps/app_practicien
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1
```

## Tests

```bash
# Depuis front/apps/app_practicien
flutter test

# Suite workspace complète (depuis front/)
dart run melos test
```

## Plan

Avancement FR2.x → [`PROGRESS.md`](../../../PROGRESS.md) — filtrer sur `[flutter-front] FR2`.

Architecture, règles et commandes → [`front/AGENTS.md`](../../AGENTS.md).
