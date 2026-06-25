# app_patient

## Mission

App mobile Nubia pour les **patients** (shell 5 onglets) : tableau de bord, mes rendez-vous,
messagerie cabinet, documents, profil, financier (devis / paiement / signature Yousign) et
notifications. `includeClinical: true` — le patient consulte ses propres données de soin.

## Run local

```bash
cd front/apps/app_patient
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1
```

## Tests

```bash
# Depuis front/apps/app_patient
flutter test

# Suite workspace complète (depuis front/)
dart run melos test
```

## Plan

Avancement FR1.x → issues Forgejo (filtre `[flutter-front] FR1`) + `git log`.

Architecture, règles et commandes → [`front/AGENTS.md`](../../AGENTS.md).
