# E2E Playwright — Harnais multi-rôle Nubia

Tests end-to-end cross-rôles (patient · praticien · secrétariat) basés sur Playwright.

## Lancement rapide

```bash
# depuis front/
melos run e2e                        # tous les scénarios
melos run e2e -- --grep _smoke       # smoke test uniquement (3 rôles)
melos run e2e -- --grep "B1"         # scénario B1 uniquement
melos run e2e -- --headed            # mode visible (non headless)

# ou directement depuis ce dossier :
cd front/test/e2e
npx playwright test
npx playwright test scenarios/_smoke.spec.ts
```

## Variables d'environnement

| Variable | Défaut (demo) | Description |
|---|---|---|
| `PATIENT_BASE_URL` | `http://localhost:4200` | URL app_patient compilée en mode web |
| `PRACTICIEN_BASE_URL` | `http://localhost:4202` | URL app_practicien |
| `SECRETARIAT_BASE_URL` | `http://localhost:4201` | URL app_secretariat |
| `API_BASE_URL` | `http://localhost:8080/v1` | URL API Rust/Axum |
| `WS_BASE_URL` | `ws://localhost:8080` | URL WebSocket |
| `CRED_PATIENT_EMAIL` | `patient1@nubia-demo.fr` | Email compte patient démo |
| `CRED_PATIENT_PASSWORD` | `demo-pass` | Mot de passe patient démo |
| `CRED_PRACTICIEN_EMAIL` | `praticien@nubia-demo.fr` | Email praticien démo |
| `CRED_PRACTICIEN_PASSWORD` | `demo-pass` | |
| `CRED_SECRETARIAT_EMAIL` | `secretariat@nubia-demo.fr` | Email secrétariat démo |
| `CRED_SECRETARIAT_PASSWORD` | `demo-pass` | |

En production/CI, ces secrets sont injectés via Infisical → secret pod → env var.

## Layout

```
front/test/e2e/
├── e2e.config.ts          # Config Playwright (timeout, retries, browser)
├── fixtures/
│   ├── helpers.ts         # loginApi(), authedFetch(), mockExternalWebhook()
│   ├── login.ts           # loginAs(role, page) — login browser Flutter
│   └── cabinet.ts         # bookAppointment(), getAgendaEvents(), etc.
└── scenarios/
    ├── _smoke.spec.ts     # Guard harnais : login 3 rôles + dashboard
    ├── _template.spec.ts  # Template commenté pour nouveaux scénarios
    ├── b1-wedge-quote-sign-pay.spec.ts
    ├── c1-c2-cloisonnement-rls.spec.ts
    └── d3-messaging-realtime.spec.ts
```

## Ajouter un scénario

1. Copier `scenarios/_template.spec.ts` → `scenarios/<code>-<titre>.spec.ts`
   (ex. `a1-booking-confirmation.spec.ts`).
2. Adapter les imports, les credentials et les steps.
3. Vérifier la référence dans `front/docs/e2e-scenarios.md`.
4. Lancer : `melos run e2e -- --grep "A1"`.

Chaque step du scénario = 1 bloc `test()` séparé pour avoir une trace d'erreur précise.
Utiliser `test.describe.configure({ mode: 'serial' })` quand les steps sont dépendants.

## Smoke test

Le smoke test (`_smoke.spec.ts`) vérifie le harnais lui-même :
- login navigateur pour chaque rôle (via `loginAs`)
- dashboard chargé (URL ≠ `/login`, nav visible)
- logout (vidage storage → auth guard redirige vers `/login`)

Si `_smoke` échoue → problème de harnais (URL, credentials, form selectors). Corriger
avant de diagnostiquer les scénarios métier.
