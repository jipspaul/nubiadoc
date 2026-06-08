# tests/flows — Harnais E2E parcours bout-en-bout

Parcours utilisateurs complets sur la **vraie API + seed** (`dev-stack`, port `:38040`).  
Distinct des specs unitaires page par page (`tests/e2e/`).

## Lancer les parcours

```bash
# Depuis web-console/
npx playwright test --project=flows

# Par rôle (alias : même testDir, projets dédiés)
npx playwright test tests/flows/ --project=patient
npx playwright test tests/flows/ --project=practitioner
npx playwright test tests/flows/ --project=secretary
```

L'URL cible par défaut est `http://localhost:38040`. Assurez-vous que le `dev-stack`
tourne avant de lancer.

## Variables d'environnement

| Variable | Défaut | Rôle |
|---|---|---|
| `FLOWS_BASE_URL` | `http://localhost:38040` | URL de base de l'app web |
| `SEED_PATIENT_EMAIL` | `patient.demo@nubia.test` | Email du compte patient seed |
| `SEED_PATIENT_PASSWORD` | `NubiaDemo1!` | Mot de passe patient seed |
| `SEED_PRACTITIONER_EMAIL` | `praticien.demo@nubia.test` | Email praticien seed |
| `SEED_PRACTITIONER_PASSWORD` | `NubiaDemo1!` | Mot de passe praticien seed |
| `SEED_SECRETARY_EMAIL` | `secretaire.demo@nubia.test` | Email secrétaire seed |
| `SEED_SECRETARY_PASSWORD` | `NubiaDemo1!` | Mot de passe secrétaire seed |

Exemple avec surcharge :

```bash
FLOWS_BASE_URL=http://localhost:38040 \
SEED_PATIENT_PASSWORD=MonPass! \
npx playwright test --project=flows
```

## Comptes seed (P2)

Créés par la migration `db/` seed P2 :

| Rôle | Email | Mot de passe |
|---|---|---|
| Patient | `patient.demo@nubia.test` | `NubiaDemo1!` |
| Praticien | `praticien.demo@nubia.test` | `NubiaDemo1!` |
| Secrétaire | `secretaire.demo@nubia.test` | `NubiaDemo1!` |

## Helpers (`helpers.ts`)

```typescript
import { loginAs, clearSession } from './helpers';

// Se connecter en tant que patient — retourne le JWT
const token = await loginAs(page, 'patient');

// Nettoyer la session entre tests
await clearSession(page);
```

`loginAs(page, role)` : navigue vers `/auth/login`, soumet les credentials seed,
attend la redirection post-login, puis retourne le JWT stocké dans `localStorage`.
Le cookie `nubia_jwt` et le cookie `nubia_role` sont posés par le JS client.

`clearSession(page)` : vide cookies + localStorage — à appeler dans `afterEach`
pour isoler les parcours.

## Structure attendue

```
tests/flows/
  helpers.ts          ← loginAs, clearSession
  README.md           ← ce fichier
  EP1-onboarding.flow.spec.ts
  EP2-search-booking.flow.spec.ts
  ...
```

Un fichier par parcours (EP*, ED*, ES*, EX*). Cf. `web-console/PLAN-ATOMIC.md §D`.

## Reset d'état entre parcours

```typescript
import { test } from '@playwright/test';
import { clearSession } from './helpers';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});
```

Pour un reset complet inter-test (y compris données API), utilisez l'endpoint
seed/reset du `dev-stack` si disponible, sinon relancez le stack.
