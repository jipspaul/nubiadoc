/**
 * ES5 — Secrétaire multi-secrétariat : sélection contexte + cloisonnement (E2E flow)
 *
 * Valide le plan multi-secrétariat (section H) :
 *   1. La secrétaire a 2 secrétariats → select-context s'affiche après login (W52/W53)
 *   2. Sélection secrétariat A → GET /v1/cabinet/agenda filtrés aux providers de A uniquement
 *   3. Switch A→B → GET /v1/cabinet/agenda filtrés aux providers de B, pas de fuite de A
 *   4. Cloisonnement : les tokens scopés portent des secretariat_id distincts + patients isolés
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2+P11+P12.
 *   - secretaire.demo@nubia.test est membre des secrétariats A et B du cabinet demo (P11)
 *   - PROVIDER_A est assigné uniquement au secrétariat A (provider_secretariat P12)
 *   - PROVIDER_B est assigné uniquement au secrétariat B (provider_secretariat P12)
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL         URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL     URL de l'API backend (défaut http://localhost:38030)
 *   SEED_CABINET_ID        UUID du cabinet demo (défaut 00000000-0000-0000-0000-000000000100)
 *   SEED_SECRETARIAT_A_ID  UUID du secrétariat A (défaut 00000000-0000-0000-0000-000000000201)
 *   SEED_SECRETARIAT_B_ID  UUID du secrétariat B (défaut 00000000-0000-0000-0000-000000000202)
 *   SEED_PROVIDER_A_ID     UUID du praticien assigné uniquement au secrétariat A
 *   SEED_PROVIDER_B_ID     UUID du praticien assigné uniquement au secrétariat B
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE = process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const CABINET_ID = process.env.SEED_CABINET_ID ?? '00000000-0000-0000-0000-000000000100';
const SECRETARIAT_A_ID = process.env.SEED_SECRETARIAT_A_ID ?? '00000000-0000-0000-0000-000000000201';
const SECRETARIAT_B_ID = process.env.SEED_SECRETARIAT_B_ID ?? '00000000-0000-0000-0000-000000000202';
const PROVIDER_A_ID = process.env.SEED_PROVIDER_A_ID ?? '00000000-0000-0000-0000-000000000301';
const PROVIDER_B_ID = process.env.SEED_PROVIDER_B_ID ?? '00000000-0000-0000-0000-000000000302';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Login secrétaire multi-secrétariat → sélecteur de contexte affiché
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire multi-secrétariat : login → page select-context avec ≥2 contextes (W52/W53)', async ({ page }) => {
  // ── 1. Connexion secrétaire ──────────────────────────────────────────────
  //    R9 : si n>1 contexte, le login retourne context_required
  //    → le front redirige vers /auth/select-context (W53)
  await loginAs(page, 'secretary');

  // ── 2. Vérification : la page de sélection de contexte est affichée ──────
  await page.waitForURL(
    (url) => url.pathname === '/auth/select-context',
    { timeout: 8_000 },
  ).catch(() => {
    /* La navigation peut être déjà accomplie avant waitForURL — on vérifie ci-dessous */
  });

  expect(
    page.url(),
    'Après login multi-secrétariat, la page doit être /auth/select-context (W53)',
  ).toContain('/auth/select-context');

  // ── 3. La liste des contextes est chargée et contient ≥2 cartes ──────────
  await expect(
    page.locator('#context-list'),
    '#context-list doit être visible une fois les contextes chargés',
  ).toBeVisible({ timeout: 10_000 });

  const cards = page.locator('#context-list article.ctx-card');
  const count = await cards.count();
  expect(
    count,
    `La secrétaire doit avoir ≥2 contextes, reçu ${count}`,
  ).toBeGreaterThanOrEqual(2);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Sélection secrétariat A → agenda filtré aux providers de A
// ─────────────────────────────────────────────────────────────────────────────
test('contexte secrétariat A → GET /v1/cabinet/agenda filtré aux providers de A, provider B absent', async ({ page }) => {
  // ── 1. Connexion secrétaire — token nu (sans secretariat_id) ─────────────
  const bareToken = await loginAs(page, 'secretary');
  expect(bareToken, 'Token secrétaire doit être non vide après login').toBeTruthy();

  const today = new Date().toISOString().slice(0, 10);

  // ── 2. Sélection contexte A + vérification agenda ────────────────────────
  const result = await page.evaluate(
    async ({
      apiBase, bareToken, cabinetId, secretariatAId, providerBId, today,
    }: {
      apiBase: string;
      bareToken: string;
      cabinetId: string;
      secretariatAId: string;
      providerBId: string;
      today: string;
    }) => {
      // POST /v1/auth/select-context → token scopé secrétariat A
      const ctxResp = await fetch(`${apiBase}/v1/auth/select-context`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${bareToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ cabinet_id: cabinetId, secretariat_id: secretariatAId }),
      });

      if (!ctxResp.ok) {
        return { selectStatus: ctxResp.status, agendaStatus: 0, secretariatIdInToken: '', providerIds: [] };
      }

      const tokens = (await ctxResp.json()) as { access_token?: string };
      const scopedToken = tokens.access_token ?? '';

      // Décoder le payload pour vérifier secretariat_id dans le JWT
      const payloadB64 = scopedToken.split('.')[1] ?? '';
      const payload = payloadB64
        ? (JSON.parse(atob(payloadB64.replace(/-/g, '+').replace(/_/g, '/'))) as Record<string, unknown>)
        : {};
      const secretariatIdInToken = (payload['secretariat_id'] as string | undefined) ?? '';

      // GET /v1/cabinet/agenda avec le token scopé secrétariat A
      const agendaResp = await fetch(
        `${apiBase}/v1/cabinet/agenda?from=${today}&to=${today}`,
        { headers: { Authorization: `Bearer ${scopedToken}` } },
      );

      const entries = agendaResp.ok
        ? (await agendaResp.json()) as Array<{
            appointments?: Array<{ provider_id?: string }>;
          }>
        : [];

      const providerIds = entries
        .flatMap((e) => e.appointments ?? [])
        .map((a) => a.provider_id)
        .filter((id): id is string => !!id);

      return {
        selectStatus: ctxResp.status,
        agendaStatus: agendaResp.status,
        secretariatIdInToken,
        providerIds,
        hasProviderB: providerIds.includes(providerBId),
      };
    },
    { apiBase: API_BASE, bareToken, cabinetId: CABINET_ID, secretariatAId: SECRETARIAT_A_ID, providerBId: PROVIDER_B_ID, today },
  );

  // ── 3. Vérifications ──────────────────────────────────────────────────────
  expect(
    result.selectStatus,
    `POST /v1/auth/select-context(A) attendu 200, reçu ${result.selectStatus}`,
  ).toBe(200);

  // Le JWT scopé doit porter secretariat_id = A
  expect(
    result.secretariatIdInToken,
    `JWT scopé doit contenir secretariat_id=${SECRETARIAT_A_ID}`,
  ).toBe(SECRETARIAT_A_ID);

  expect(
    result.agendaStatus,
    `GET /v1/cabinet/agenda(contexte A) attendu 200, reçu ${result.agendaStatus}`,
  ).toBe(200);

  // Cloisonnement : le provider du secrétariat B ne doit pas apparaître dans le contexte A
  expect(
    result.hasProviderB,
    `Provider du secrétariat B (${PROVIDER_B_ID}) ne doit pas apparaître dans l'agenda du contexte A`,
  ).toBe(false);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 3 : Switch A→B → agenda filtré aux providers de B, pas de fuite de A
// ─────────────────────────────────────────────────────────────────────────────
test('switch contexte A→B → GET /v1/cabinet/agenda filtrés aux providers de B, provider A absent', async ({ page }) => {
  // ── 1. Connexion secrétaire ──────────────────────────────────────────────
  const bareToken = await loginAs(page, 'secretary');
  expect(bareToken, 'Token secrétaire doit être non vide après login').toBeTruthy();

  const today = new Date().toISOString().slice(0, 10);

  // ── 2. Sélection A puis switch vers B + vérification ─────────────────────
  const result = await page.evaluate(
    async ({
      apiBase, bareToken, cabinetId, secretariatAId, secretariatBId, providerAId, today,
    }: {
      apiBase: string;
      bareToken: string;
      cabinetId: string;
      secretariatAId: string;
      secretariatBId: string;
      providerAId: string;
      today: string;
    }) => {
      // Sélectionner contexte A
      const ctxAResp = await fetch(`${apiBase}/v1/auth/select-context`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${bareToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ cabinet_id: cabinetId, secretariat_id: secretariatAId }),
      });
      const tokensA = ctxAResp.ok ? (await ctxAResp.json()) as { access_token?: string } : {};
      // Utiliser le token A comme base pour le switch (simule l'appli qui switche depuis A vers B)
      const tokenAfterA = tokensA.access_token ?? bareToken;

      // Switch vers contexte B
      const ctxBResp = await fetch(`${apiBase}/v1/auth/select-context`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${tokenAfterA}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ cabinet_id: cabinetId, secretariat_id: secretariatBId }),
      });

      if (!ctxBResp.ok) {
        return { selectBStatus: ctxBResp.status, agendaStatus: 0, secretariatIdInToken: '', hasProviderA: false };
      }

      const tokensB = (await ctxBResp.json()) as { access_token?: string };
      const tokenB = tokensB.access_token ?? '';

      // Décoder le payload du token B
      const payloadB64 = tokenB.split('.')[1] ?? '';
      const payload = payloadB64
        ? (JSON.parse(atob(payloadB64.replace(/-/g, '+').replace(/_/g, '/'))) as Record<string, unknown>)
        : {};
      const secretariatIdInToken = (payload['secretariat_id'] as string | undefined) ?? '';

      // GET /v1/cabinet/agenda avec le token scopé secrétariat B
      const agendaResp = await fetch(
        `${apiBase}/v1/cabinet/agenda?from=${today}&to=${today}`,
        { headers: { Authorization: `Bearer ${tokenB}` } },
      );

      const entries = agendaResp.ok
        ? (await agendaResp.json()) as Array<{
            appointments?: Array<{ provider_id?: string }>;
          }>
        : [];

      const providerIds = entries
        .flatMap((e) => e.appointments ?? [])
        .map((a) => a.provider_id)
        .filter((id): id is string => !!id);

      return {
        selectBStatus: ctxBResp.status,
        agendaStatus: agendaResp.status,
        secretariatIdInToken,
        hasProviderA: providerIds.includes(providerAId),
      };
    },
    {
      apiBase: API_BASE, bareToken,
      cabinetId: CABINET_ID,
      secretariatAId: SECRETARIAT_A_ID, secretariatBId: SECRETARIAT_B_ID,
      providerAId: PROVIDER_A_ID,
      today,
    },
  );

  // ── 3. Vérifications ──────────────────────────────────────────────────────
  expect(
    result.selectBStatus,
    `POST /v1/auth/select-context(B) attendu 200, reçu ${result.selectBStatus}`,
  ).toBe(200);

  // Le JWT scopé B doit porter secretariat_id = B (pas A)
  expect(
    result.secretariatIdInToken,
    `JWT scopé B doit contenir secretariat_id=${SECRETARIAT_B_ID}, reçu ${result.secretariatIdInToken}`,
  ).toBe(SECRETARIAT_B_ID);

  expect(
    result.agendaStatus,
    `GET /v1/cabinet/agenda(contexte B) attendu 200, reçu ${result.agendaStatus}`,
  ).toBe(200);

  // Cloisonnement : le provider du secrétariat A ne doit pas apparaître dans le contexte B
  expect(
    result.hasProviderA,
    `Provider du secrétariat A (${PROVIDER_A_ID}) ne doit pas fuiter dans l'agenda du contexte B`,
  ).toBe(false);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 4 : Cloisonnement — patients contexte A ≠ contexte B
// ─────────────────────────────────────────────────────────────────────────────
test('cloisonnement : GET /v1/cabinet/patients diffère entre contexte A et contexte B', async ({ page }) => {
  // ── 1. Connexion secrétaire ──────────────────────────────────────────────
  const bareToken = await loginAs(page, 'secretary');
  expect(bareToken, 'Token secrétaire doit être non vide après login').toBeTruthy();

  // ── 2. Récupérer les patients sous chaque contexte ────────────────────────
  const result = await page.evaluate(
    async ({
      apiBase, bareToken, cabinetId, secretariatAId, secretariatBId,
    }: {
      apiBase: string;
      bareToken: string;
      cabinetId: string;
      secretariatAId: string;
      secretariatBId: string;
    }) => {
      async function selectContext(parentToken: string, secretariatId: string): Promise<{ status: number; token: string }> {
        const resp = await fetch(`${apiBase}/v1/auth/select-context`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${parentToken}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ cabinet_id: cabinetId, secretariat_id: secretariatId }),
        });
        if (!resp.ok) return { status: resp.status, token: '' };
        const data = (await resp.json()) as { access_token?: string };
        return { status: resp.status, token: data.access_token ?? '' };
      }

      async function getPatients(token: string): Promise<{ status: number; ids: string[] }> {
        if (!token) return { status: 0, ids: [] };
        const resp = await fetch(`${apiBase}/v1/cabinet/patients`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        const patients = resp.ok ? (await resp.json()) as Array<{ id: string }> : [];
        return { status: resp.status, ids: patients.map((p) => p.id) };
      }

      const ctxA = await selectContext(bareToken, secretariatAId);
      const ctxB = await selectContext(bareToken, secretariatBId);

      const patientsA = await getPatients(ctxA.token);
      const patientsB = await getPatients(ctxB.token);

      // Un patient du secrétariat A ne doit pas apparaître dans le secrétariat B
      const leakAtoB = patientsA.ids.filter((id) => patientsB.ids.includes(id));
      const leakBtoA = patientsB.ids.filter((id) => patientsA.ids.includes(id));

      return {
        selectAStatus: ctxA.status,
        selectBStatus: ctxB.status,
        patientsAStatus: patientsA.status,
        patientsBStatus: patientsB.status,
        countA: patientsA.ids.length,
        countB: patientsB.ids.length,
        // intersection = fuite de cloisonnement (ok si les deux listes sont vides)
        leakCount: leakAtoB.length + leakBtoA.length,
      };
    },
    {
      apiBase: API_BASE, bareToken,
      cabinetId: CABINET_ID,
      secretariatAId: SECRETARIAT_A_ID,
      secretariatBId: SECRETARIAT_B_ID,
    },
  );

  // ── 3. Vérifications ──────────────────────────────────────────────────────
  expect(
    result.selectAStatus,
    `POST select-context(A) attendu 200, reçu ${result.selectAStatus}`,
  ).toBe(200);
  expect(
    result.selectBStatus,
    `POST select-context(B) attendu 200, reçu ${result.selectBStatus}`,
  ).toBe(200);

  expect(
    result.patientsAStatus,
    `GET /v1/cabinet/patients(A) attendu 200, reçu ${result.patientsAStatus}`,
  ).toBe(200);
  expect(
    result.patientsBStatus,
    `GET /v1/cabinet/patients(B) attendu 200, reçu ${result.patientsBStatus}`,
  ).toBe(200);

  // Si des patients existent dans les deux listes, il ne doit y avoir aucune fuite
  // (RLS filtre par secretariat_id via app.current_secretariat_id — P13)
  if (result.countA > 0 && result.countB > 0) {
    expect(
      result.leakCount,
      `${result.leakCount} patient(s) présents dans les deux contextes — cloisonnement RLS (P13) défaillant`,
    ).toBe(0);
  }
});
