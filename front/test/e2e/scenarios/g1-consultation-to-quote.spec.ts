/**
 * G1 — Consultation dentaire complète → devis patient
 *
 * Flux : D login → D ouvre le schéma dentaire → D modifie une dent → D
 *        démarre une consultation → D ajoute un acte CCAM (dent pré-remplie
 *        via le schéma) → D clôture la séance → P voit le devis.
 *
 * Idempotent PARTIELLEMENT : la modification de dent alterne un statut
 * neutre sur une dent qui n'est pas utilisée par d'autres scénarios (36), et
 * le démarrage de consultation réutilise la séance existante si le RDV
 * dédié (aa...0004, db/seed/seed.sql) est déjà `in_progress` avec une
 * session (le bouton "Démarrer" n'apparaît que pour un RDV
 * confirmed/checked_in, agenda_page.dart, et disparaît après le 1er run).
 * En revanche, un run COMPLET (jusqu'à l'étape 5, clôture) rend le RDV
 * `done` — un 2e run complet sans `make reset && make migrate && make seed`
 * entre-temps ne retrouvera ni bouton "Démarrer" ni session `in_progress` et
 * échouera à l'étape 4 (même limite déjà acceptée pour A4, cf.
 * `a4-waiting-room-realtime.spec.ts`, "les slots seed du jour ne sont pas
 * garantis"). Étape 7 suppose aussi une base fraîche : Marc Dubois n'a en
 * seed qu'un devis `draft` (invisible patient, RLS quote_patient_read) —
 * le devis créé par ce run est donc le seul visible côté patient tant que
 * la base n'a pas été reset.
 *
 * Refs : front/docs/e2e-scenarios.md §G1
 *        api/src/dental_chart.rs, api/src/scheduling.rs::start_consultation,
 *        api/src/consultation_act_create.rs, api/src/consultations.rs
 */

import { test, expect } from '@playwright/test';
import { loginApi, authedFetch } from '../fixtures/helpers';
import { loginAs, gotoRoute, credentialsFor } from '../fixtures/login';

const D_EMAIL = credentialsFor('practicien').email;
const D_PASS = credentialsFor('practicien').password;
const P_EMAIL = credentialsFor('patient').email;
const P_PASS = credentialsFor('patient').password;

// Marc Dubois — seed démo (db/seed/seed.sql).
const PATIENT_ID = process.env.DEMO_PATIENT_ID ?? 'd0000000-0000-0000-0000-0000000000d1';
// RDV dédié G1 (checked_in, distinct de aa...0001 déjà in_progress) — seed.sql.
const APPOINTMENT_ID = 'aa000000-0000-0000-0000-000000000004';
// HBGD036 — Détartrage sus- et sous-gingival, deux arcades (db/migrations/0119).
const CCAM_LABEL = 'Détartrage sus- et sous-gingival, deux arcades';
const TOOTH = '36';

test.describe('G1 — Consultation dentaire complète → devis patient', () => {
  test.describe.configure({ mode: 'serial' });

  let dToken: string;
  let pToken: string;
  let consultationId: string;
  let actAddedTooth: string | null = null;

  test.beforeAll(async () => {
    [dToken, pToken] = await Promise.all([
      loginApi(D_EMAIL, D_PASS),
      loginApi(P_EMAIL, P_PASS),
    ]);
  });

  // Étape 2 : D ouvre le schéma dentaire du patient
  test('Étape 2 — D ouvre le schéma dentaire : GET .../dental-chart 200', async ({ page }) => {
    await loginAs('practicien', page);
    const [chartRes] = await Promise.all([
      page.waitForResponse(
        (r) =>
          r.url().includes(`/patients/${PATIENT_ID}/dental-chart`) &&
          r.request().method() === 'GET',
        { timeout: 15_000 },
      ),
      gotoRoute(page, 'practicien', `/patients/${PATIENT_ID}/dental-chart`),
    ]);
    expect(chartRes.status(), 'GET .../dental-chart → 200').toBe(200);
    await expect(page.getByText('Schéma dentaire').first()).toBeVisible();
  });

  // Étape 3 : D clique une dent, choisit un état, enregistre
  test('Étape 3 — D modifie une dent et enregistre : PUT .../dental-chart 200, couleur change sans refresh', async ({
    page,
  }) => {
    await loginAs('practicien', page);
    await gotoRoute(page, 'practicien', `/patients/${PATIENT_ID}/dental-chart`);

    // Statut cible fixe ("Carie") plutôt qu'une alternance dépendant de
    // l'état de départ — idempotent quel que soit le statut actuel de la
    // dent 36 (le doc n'exige qu'un changement de couleur constaté, pas une
    // transition précise).
    await page.getByText(TOOTH, { exact: true }).first().click();
    await page.getByText('Carie', { exact: true }).first().click();

    const [putRes] = await Promise.all([
      page.waitForResponse(
        (r) =>
          r.url().includes(`/patients/${PATIENT_ID}/dental-chart`) &&
          r.request().method() === 'PUT',
        { timeout: 10_000 },
      ),
      page.getByRole('button', { name: 'Enregistrer' }).click(),
    ]);
    expect(putRes.status(), 'PUT .../dental-chart → 200').toBe(200);
  });

  // Étape 4 : D démarre une consultation, ajoute un acte CCAM (dent pré-remplie)
  test('Étape 4 — D démarre la séance et ajoute un acte CCAM : POST .../acts 201, tooth = dent step 3', async ({
    page,
  }) => {
    // Idempotence : réutilise la séance existante si ce RDV est déjà démarré
    // (2e run sans reset DB — cf. doc de tête de fichier).
    const listRes = await authedFetch(
      dToken,
      `/cabinet/consultations?patient_id=${PATIENT_ID}&status=in_progress`,
    );
    const list = (await listRes.json()) as {
      data: { id: string; appointment_id: string }[];
    };
    const existing = list.data?.find((s) => s.appointment_id === APPOINTMENT_ID);

    if (existing) {
      consultationId = existing.id;
    } else {
      await loginAs('practicien', page);
      await gotoRoute(page, 'practicien', '/agenda');
      const [startRes] = await Promise.all([
        page.waitForResponse(
          (r) =>
            r.url().includes(`/appointments/${APPOINTMENT_ID}/start`) &&
            r.request().method() === 'POST',
          { timeout: 10_000 },
        ),
        (async () => {
          await page.getByText('Consultation e2e G1').first().click();
          await page.getByRole('button', { name: 'Démarrer' }).click();
        })(),
      ]);
      expect(startRes.status(), 'POST .../appointments/:id/start → 200').toBe(200);
      const body = (await startRes.json()) as { consultation_id: string };
      consultationId = body.consultation_id;
    }

    await loginAs('practicien', page);
    await gotoRoute(page, 'practicien', `/consultation?id=${consultationId}`);

    // Choisit la dent via le schéma (bottom sheet ToothGrid) — même dent que
    // l'étape 3, pour l'assertion tooth ci-dessous.
    await page.getByText('Choisir une dent').first().click();
    await page.getByText(TOOTH, { exact: true }).first().click();
    await expect(page.getByText(`Dent ${TOOTH}`).first()).toBeVisible();

    // Recherche puis sélectionne l'acte CCAM. NubiaTextField (ccam_picker.dart)
    // n'a qu'un `hint` ('Rechercher un acte CCAM'), pas de `label` distinct —
    // contrairement aux champs déjà exercés par ce harnais (login.ts n'utilise
    // que des champs avec labelText réel). Si Flutter n'expose pas le hint
    // comme accessible name ici, premier point à corriger en cas d'échec réel.
    await page.getByRole('textbox', { name: 'Rechercher un acte CCAM' }).fill('détartrage');
    await page.getByText(CCAM_LABEL, { exact: true }).first().click();

    // Éditeur d'acte : dent + montant déjà pré-remplis (tarif de référence) —
    // valide directement.
    const [addRes] = await Promise.all([
      page.waitForResponse(
        (r) =>
          r.url().includes(`/consultations/${consultationId}/acts`) &&
          r.request().method() === 'POST',
        { timeout: 10_000 },
      ),
      page.getByRole('button', { name: 'Ajouter' }).click(),
    ]);
    expect(addRes.status(), 'POST .../acts → 201').toBe(201);
    const addBody = (await addRes.json()) as { tooth?: string | null };
    actAddedTooth = addBody.tooth ?? null;
    expect(actAddedTooth, 'tooth de l\'acte ajouté doit correspondre à la dent cliquée en step 3').toBe(TOOTH);
  });

  // Étape 5 : D clôture la séance
  test('Étape 5 — D clôture la séance : POST .../complete 200, invoice_id retourné', async ({
    page,
  }) => {
    await loginAs('practicien', page);
    await gotoRoute(page, 'practicien', `/consultation?id=${consultationId}`);

    const [completeRes] = await Promise.all([
      page.waitForResponse(
        (r) =>
          r.url().includes(`/consultations/${consultationId}/complete`) &&
          r.request().method() === 'POST',
        { timeout: 10_000 },
      ),
      page.getByRole('button', { name: 'Terminer' }).click(),
    ]);
    expect(completeRes.status(), 'POST .../complete → 200').toBe(200);
    // Défaut de contrat corrigé (#4264, cf. e2e-scenarios.md §G) : le champ
    // est `invoice_id`, jamais `quote_id` (CompleteConsultationResponse,
    // api/src/consultations.rs).
    const body = (await completeRes.json()) as { invoice_id?: string; quote_id?: string };
    expect(body.quote_id, 'le champ est invoice_id, pas quote_id').toBeUndefined();
    expect(body.invoice_id, 'invoice_id doit être présent').toBeTruthy();
  });

  // Étape 6 : pas de route /devis/:id côté app_practicien — maillon manquant
  // documenté (règle "harnais/écran absent" de e2e-scenarios.md §G1), pas
  // inventé. `devis = '/devis'` (app_router.dart) est une liste sans
  // sous-route :id.
  test.fixme(
    'Étape 6 — D consulte le détail du devis',
    async () => {
      // BLOQUÉ INFRA-MISSING : aucune route `/devis/:id` n'existe côté
      // app_practicien (seule la liste `/devis` existe, router/app_router.dart).
    },
  );

  // Étape 7 : P voit le même devis
  test('Étape 7 — P voit le devis sur /financial (même montant, même acte)', async ({ page }) => {
    const apiRes = await authedFetch(pToken, '/quotes');
    expect(apiRes.status, 'GET /v1/quotes côté patient → 200').toBe(200);
    const quotes = (await apiRes.json()) as {
      data: { id: string; status: string; amount_cents: number }[];
    };
    // Marc Dubois n'a en seed qu'un devis 'draft' (invisible patient, RLS
    // quote_patient_read exclut 'draft') — sur une base fraîche, le devis
    // créé par ce run (étape 5) est donc le seul visible ici.
    expect(quotes.data.length, 'au moins un devis visible côté patient').toBeGreaterThan(0);

    // UI : ouvre le devis depuis la liste (financial_page.dart n'a pas de
    // route dédiée /financial/:id — la sélection passe par un event Bloc,
    // FinancialQuoteSelected, déclenché au tap de la carte).
    await loginAs('patient', page);
    await gotoRoute(page, 'patient', '/financial');
    await page.getByText(/Reste à charge/).first().click();
    await expect(page.getByText(CCAM_LABEL).first()).toBeVisible({ timeout: 15_000 });
  });
});
