/**
 * TEMPLATE — scénario E2E cross-rôle
 *
 * Copier ce fichier, renommer en `<code>-<titre-court>.spec.ts`
 * (ex. `a1-booking-confirmation.spec.ts`) et adapter les sections marquées TODO.
 *
 * Référence scénarios : front/docs/e2e-scenarios.md
 * Persona qui lance    : agents/personas/flutter-qa-agent.md (mode e2e)
 * Lancement            : melos run e2e -- --grep "A1"
 */

// ── Imports ──────────────────────────────────────────────────────────────────

import { test, expect } from '@playwright/test';

// Auth API (obtenir un JWT sans browser) :
import { loginApi, authedFetch } from '../fixtures/helpers';

// Auth browser (login complet avec page Flutter) :
import { loginAs, baseUrlFor } from '../fixtures/login';

// Helpers métier API (booking, agenda…) :
// import { bookAppointment, getAgendaEvents, confirmAppointment } from '../fixtures/cabinet';

// ── Credentials (env vars ou fallback demo) ───────────────────────────────────

const P_EMAIL  = process.env.CRED_PATIENT_EMAIL     ?? 'patient1@nubia-demo.fr';
const P_PASS   = process.env.CRED_PATIENT_PASSWORD  ?? 'demo-pass';
const S_EMAIL  = process.env.CRED_SECRETARIAT_EMAIL    ?? 'secretariat@nubia-demo.fr';
const S_PASS   = process.env.CRED_SECRETARIAT_PASSWORD ?? 'demo-pass';
const D_EMAIL  = process.env.CRED_PRACTICIEN_EMAIL    ?? 'praticien@nubia-demo.fr';
const D_PASS   = process.env.CRED_PRACTICIEN_PASSWORD ?? 'demo-pass';

// ── TODO : remplacer "XX — Titre scénario" par le code réel ─────────────────

test.describe('XX — Titre scénario (P0/P1)', () => {
  // mode: 'serial' garantit l'ordre des steps dépendants.
  // Supprimer si les tests sont indépendants.
  test.describe.configure({ mode: 'serial' });

  // Tokens API — initialisés dans beforeAll
  let pToken: string;
  let sToken: string;
  // let dToken: string;

  // IDs partagés entre steps
  // let appointmentId: string;

  // ── Setup ─────────────────────────────────────────────────────────────────

  test.beforeAll(async () => {
    // Authentification API parallèle (plus rapide que le browser login)
    [pToken, sToken] = await Promise.all([
      loginApi(P_EMAIL, P_PASS),
      loginApi(S_EMAIL, S_PASS),
      // loginApi(D_EMAIL, D_PASS),  // décommenter si D est impliqué
    ]);
    // TODO : seed ou pré-conditions API (ex. créer un RDV de base)
  });

  // ── Step 1 : <Acteur> <Action> ────────────────────────────────────────────

  test('Step 1 — <description courte>', async ({ page }) => {
    // Exemple : action via API
    const res = await authedFetch(pToken, '/appointments');
    expect(res.status, 'GET /appointments → 200').toBe(200);

    // TODO : assertions métier
  });

  // ── Step 2 : <Acteur> <Action> (browser) ─────────────────────────────────

  test('Step 2 — <description courte> (UI)', async ({ page }) => {
    // Exemple : action via browser Flutter
    const { page: sPage } = await loginAs('secretariat', page);
    await sPage.goto(`${baseUrlFor('secretariat')}/agenda`);
    await sPage.waitForLoadState('networkidle');

    // TODO : assertions UI
    // await expect(sPage.getByTestId('agenda-event-xxx')).toBeVisible();
  });

  // ── Step N … ─────────────────────────────────────────────────────────────

  // Dupliquer le bloc test() ci-dessus pour chaque step du scénario.
  // Chaque step = 1 test() pour une trace d'erreur précise.
});
