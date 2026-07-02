# E2E Playwright — Harnais multi-rôle Nubia

Tests end-to-end cross-rôles (patient · praticien · secrétariat) basés sur Playwright.

## Lancement rapide

```bash
# depuis front/
melos run e2e                        # tous les scénarios
melos run e2e -- --grep _smoke       # smoke test uniquement (3 rôles)
melos run e2e -- --grep "B1"         # scénario B1 uniquement
melos run e2e -- --headed            # mode visible (non headless)

# ou directement depuis ce dossier (le --config est OBLIGATOIRE — sans lui
# Playwright prend sa config par défaut : _template s'exécute, workers
# parallèles, et le rate-limit login explose) :
cd front/test/e2e
npx playwright test --config=e2e.config.ts
npx playwright test --config=e2e.config.ts scenarios/_smoke.spec.ts
```

## Variables d'environnement

| Variable | Défaut (seed démo) | Description |
|---|---|---|
| `PATIENT_BASE_URL` | `http://localhost:4200` | URL app_patient compilée en mode web |
| `PRACTICIEN_BASE_URL` | `http://localhost:4202` | URL app_practicien |
| `SECRETARIAT_BASE_URL` | `http://localhost:4201` | URL app_secretariat |
| `API_BASE_URL` | `http://localhost:8080/v1` | URL API Rust/Axum |
| `WS_BASE_URL` | `ws://localhost:8080` | URL WebSocket |
| `CRED_PATIENT_EMAIL` | `marc.dubois@patient.test` | Compte patient seed (`db/seed/`) |
| `CRED_PATIENT_PASSWORD` | `Nubia2026!` | Mot de passe démo commun |
| `CRED_PRACTICIEN_EMAIL` | `hugo.marin@cabinet-lyon.test` | Praticien seed |
| `CRED_SECRETARIAT_EMAIL` | `sonia.accueil@cabinet-lyon.test` | Secrétaire seed |
| `CRED_PATIENT2_EMAIL` | `patient.reset@nubia.test` | 2ᵉ patient (tests RLS C2), mdp `NubiaDemo1!` |

Contre l'environnement de test déployé :
`PATIENT_BASE_URL=https://patient.doc.nubia-link.com` (idem praticien/secretariat),
`API_BASE_URL=https://api.doc.nubia-link.com/v1`. En CI, secrets via Infisical.

## Spécificités Flutter web (LIRE avant d'écrire un scénario)

1. **Sémantique** : Flutter rend sur canvas — l'arbre ARIA n'existe qu'après un
   clic sur le bouton hors-écran « Enable accessibility ». `gotoRoute()` des
   fixtures s'en charge. Sans ça, `getByLabel`/`getByRole` ne voient RIEN.
2. **Pas de `data-testid`** : `getByTestId` ne matche jamais. S'appuyer sur les
   rôles/labels sémantiques (`getByRole('button', {name})`, `getByText`).
3. **Routing hybride** : app_practicien = path (`/login`) ; patient et
   secretariat = hash (`/#/login`). JAMAIS de `page.goto`/`toHaveURL` bruts —
   utiliser `gotoRoute()`, `currentRoute()`, `waitForRoutePrefix()`.
4. **Saisie** : `pressSequentially` (frappe réelle), pas `fill()` — les inputs
   sémantiques Flutter perdent parfois une valeur posée programmatiquement.
5. **Rate-limit login** : l'API plafonne `/auth/login` à **5/min par IP** et
   10/5min par email. Le harnais sérialise tout (workers=1), espace les logins
   (`loginThrottle()`, 13s), met en cache le token API par email et la session
   navigateur par rôle (1 login formulaire par rôle et par run, réinjection
   `localStorage` ensuite). Ne JAMAIS ajouter un login direct dans un spec —
   passer par `loginAs`/`loginApi`.
6. **IDs seed** : les créneaux sont régénérés chaque jour → `findOpenSlot()`
   plutôt qu'un SLOT_ID en dur. Les UUIDs stables (cabinet, providers,
   patients) sont dans `db/seed/seed.sql`.
7. **Contrats API** : la clé des objets est `id` (pas `appointment_id` /
   `quote_id` / `conversation_id`) — vérifier la struct Rust avant d'écrire
   une assertion (`api/src/*.rs`).

## Layout

```
front/test/e2e/
├── e2e.config.ts          # Config Playwright (workers=1, _template exclu)
├── fixtures/
│   ├── helpers.ts         # loginApi() (throttle + cache), authedFetch(), mockExternalWebhook()
│   ├── login.ts           # loginAs(), gotoRoute(), waitForRoutePrefix(), credentialsFor()
│   └── cabinet.ts         # bookAppointment(), findOpenSlot(), confirmAppointment()…
└── scenarios/
    ├── _smoke.spec.ts     # Guard harnais : login 3 rôles + dashboard
    ├── _template.spec.ts  # Template commenté (EXCLU de l'exécution)
    ├── a1-booking-confirmation.spec.ts
    ├── a4-waiting-room-realtime.spec.ts
    ├── b1-wedge-quote-sign-pay.spec.ts
    ├── c1-c2-cloisonnement-rls.spec.ts
    └── d3-messaging-realtime.spec.ts
```

## Ajouter un scénario

1. Copier `scenarios/_template.spec.ts` → `scenarios/<code>-<titre>.spec.ts`
   (ex. `a2-annulation.spec.ts`).
2. Utiliser exclusivement les fixtures (`loginAs`, `gotoRoute`, `credentialsFor`,
   `findOpenSlot`) — relire « Spécificités Flutter web » ci-dessus.
3. Vérifier la référence dans `front/docs/e2e-scenarios.md`.
4. Lancer : `melos run e2e -- --grep "A2"`.

Chaque step du scénario = 1 bloc `test()` séparé pour avoir une trace d'erreur précise.
Utiliser `test.describe.configure({ mode: 'serial' })` quand les steps sont dépendants.
Un step bloqué par une route API manquante = `test.fixme(...)` + commentaire
`BLOQUÉ API` avec référence d'issue — jamais un test qui échoue en permanence.

## Smoke test

Le smoke test (`_smoke.spec.ts`) vérifie le harnais lui-même :
- login navigateur pour chaque rôle (via `loginAs`)
- dashboard chargé (route ≠ `/login`, arbre sémantique rendu)
- logout (vidage storage + reload → l'auth guard redirige vers `/login`)

Si `_smoke` échoue → problème de harnais (URL, credentials, sémantique). Corriger
avant de diagnostiquer les scénarios métier.
