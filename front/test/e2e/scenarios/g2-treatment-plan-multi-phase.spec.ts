/**
 * G2 — Plan de traitement multi-étapes
 *
 * Flux : D crée un plan → D ajoute 2 phases avec un acte CCAM chacune → P
 *        voit le plan (écran patient, #4261) → D marque la phase 1 réalisée
 *        (#4262) → visible côté D et P après refresh.
 *
 * L'attachement d'un acte CCAM à la création de phase (`inline_acts`, #4263)
 * n'est pas encore exposé dans l'UI praticien (`_promptNewPhase`,
 * treatment_plans_page.dart, ne propose qu'un champ titre) — step 2 pilote
 * donc cette partie via l'API, comme la réservation de créneau dans A1/A4.
 * Le changement de statut de phase (#4262) n'a pas non plus de bouton UI
 * (`phase.status` est affiché en lecture seule) — step 4 pilote la mutation
 * via l'API et vérifie la propagation par un simple refresh, conformément à
 * l'assertion du doc ("côté D, et côté P après refresh").
 *
 * Idempotent : plan/phases créés avec un titre horodaté (comme motif dans
 * A1/A4) → chaque run crée ses propres ressources, aucun nettoyage requis.
 *
 * Refs : front/docs/e2e-scenarios.md §G2
 *        api/src/treatment_plans.rs, api/src/treatment_phases.rs
 */

import { test, expect } from '@playwright/test';
import { loginApi, authedFetch } from '../fixtures/helpers';
import { loginAs, gotoRoute, credentialsFor } from '../fixtures/login';

const D_EMAIL = credentialsFor('practicien').email;
const D_PASS = credentialsFor('practicien').password;
const P_EMAIL = credentialsFor('patient').email;
const P_PASS = credentialsFor('patient').password;

// Marc Dubois — seed démo (db/seed/seed.sql). Login patient par défaut du
// harnais (fixtures/login.ts) — cohérent avec le compte utilisé côté API.
const PATIENT_ID = process.env.DEMO_PATIENT_ID ?? 'd0000000-0000-0000-0000-0000000000d1';

test.describe('G2 — Plan de traitement multi-étapes', () => {
  test.describe.configure({ mode: 'serial' });

  let dToken: string;
  let pToken: string;
  let planId: string;
  let phase1Id: string;
  const planTitle = `e2e-g2-${Date.now().toString(36)}`;

  test.beforeAll(async () => {
    [dToken, pToken] = await Promise.all([
      loginApi(D_EMAIL, D_PASS),
      loginApi(P_EMAIL, P_PASS),
    ]);
  });

  // Étape 1 : D crée un plan de traitement (UI)
  test('Étape 1 — D crée un plan de traitement : POST .../treatment-plans 201', async ({
    page,
  }) => {
    await loginAs('practicien', page);
    await gotoRoute(page, 'practicien', `/patients/${PATIENT_ID}/treatment-plans`);

    // Le FAB n'avait pas de `tooltip` (donc pas de nom accessible exploitable
    // par un sélecteur ARIA) — ajouté en écrivant ce spec
    // (treatment_plans_page.dart) plutôt que de cibler par position.
    await page
      .getByRole('button', { name: 'Nouveau plan de traitement' })
      .click();
    await page.getByRole('textbox', { name: 'Titre du plan' }).fill(planTitle);

    const [createRes] = await Promise.all([
      page.waitForResponse(
        (r) => r.url().includes('/cabinet/treatment-plans') && r.request().method() === 'POST',
        { timeout: 10_000 },
      ),
      page.getByRole('button', { name: 'Créer' }).click(),
    ]);
    expect(createRes.status(), 'POST .../treatment-plans → 201').toBe(201);
    const body = (await createRes.json()) as { plan_id: string };
    planId = body.plan_id;
    expect(planId, 'plan_id doit être retourné').toBeTruthy();
  });

  // Étape 2 : D ajoute 2 phases, chacune avec un acte CCAM rattaché (API —
  // inline_acts non exposé côté UI, cf. doc de tête de fichier)
  test('Étape 2 — D ajoute 2 phases avec acte CCAM : POST .../phases 201 ×2', async () => {
    const phase1Res = await authedFetch(dToken, `/cabinet/treatment-plans/${planId}/phases`, {
      method: 'POST',
      body: JSON.stringify({
        title: 'Phase 1 · Assainissement',
        position: 1,
        inline_acts: [{ label: 'Détartrage', ccam_code: 'HBGD036', amount_cents: 2864 }],
      }),
    });
    expect(phase1Res.status, 'POST .../phases (phase 1) → 201').toBe(201);
    const phase1Body = (await phase1Res.json()) as { phase_id: string };
    phase1Id = phase1Body.phase_id;

    const phase2Res = await authedFetch(dToken, `/cabinet/treatment-plans/${planId}/phases`, {
      method: 'POST',
      body: JSON.stringify({
        title: 'Phase 2 · Chirurgie implantaire',
        position: 2,
        inline_acts: [{ label: 'Pose implant', ccam_code: 'LBLD017', amount_cents: 120000 }],
      }),
    });
    expect(phase2Res.status, 'POST .../phases (phase 2) → 201').toBe(201);
  });

  // Étape 3 : P voit le plan avec les 2 phases, actes + statut par phase
  test('Étape 3 — P voit le plan sur /treatment-plans/:id (2 phases, actes, statuts)', async ({
    page,
  }) => {
    const detailRes = await authedFetch(pToken, `/treatment-plans/${planId}`);
    expect(detailRes.status, 'GET /v1/treatment-plans/:id côté patient → 200').toBe(200);
    const detail = (await detailRes.json()) as { phases: { title: string }[] };
    expect(detail.phases.length, '2 phases visibles côté patient').toBe(2);

    await loginAs('patient', page);
    await gotoRoute(page, 'patient', `/treatment-plans/${planId}`);
    await expect(page.getByText('Phase 1 · Assainissement').first()).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByText('Phase 2 · Chirurgie implantaire').first()).toBeVisible();
    await expect(page.getByText('Détartrage').first()).toBeVisible();
  });

  // Étape 4 : D marque la phase 1 réalisée
  test('Étape 4 — D marque la phase 1 réalisée : visible côté D et P après refresh', async ({
    page,
  }) => {
    const patchRes = await authedFetch(
      dToken,
      `/cabinet/treatment-plans/${planId}/phases/${phase1Id}`,
      { method: 'PATCH', body: JSON.stringify({ status: 'done' }) },
    );
    expect(patchRes.status, 'PATCH .../phases/:id → 200').toBe(200);
    const patchBody = (await patchRes.json()) as { status: string };
    expect(patchBody.status).toBe('done');

    // Côté D : statut brut affiché tel quel (treatment_plans_page.dart,
    // Text(phase.status) — pas de libellé traduit côté praticien).
    await loginAs('practicien', page);
    await gotoRoute(page, 'practicien', `/patients/${PATIENT_ID}/treatment-plans`);
    await expect(
      page.getByText('Phase 1 · Assainissement').first(),
      'la phase 1 doit rester visible côté D',
    ).toBeVisible({ timeout: 15_000 });

    // Côté P : libellé traduit (treatment_plan_detail_page.dart, #4261) —
    // refresh (nouvelle navigation, pas de WS branché sur ce flux).
    const pPage = await page.context().newPage();
    await loginAs('patient', pPage);
    await gotoRoute(pPage, 'patient', `/treatment-plans/${planId}`);
    await expect(pPage.getByText('Réalisée').first()).toBeVisible({ timeout: 15_000 });
    await pPage.close();
  });
});
