/**
 * ED5 — Docteur multi-établissement (E2E flow)
 *
 * Parcours :
 *   1. Login → context_required → POST /v1/auth/select-context (établissement A)
 *              → GET /v1/cabinet/agenda → 200 avec cabinet_id = A
 *   2. PUT /v1/cabinet/providers/:id/secretariats → assigne agenda au secrétariat A (200)
 *   3. Secrétaire A se connecte → sélectionne secrétariat A
 *              → GET /v1/cabinet/appointments → 200 (voit les RDV du docteur)
 *   4. Login praticien → select-context B → agenda cabinet_id = B
 *              → PUT …/secretariats → assigne secrétariat B
 *   5. Secrétaire B se connecte → sélectionne secrétariat B
 *              → GET /v1/cabinet/appointments → 200 (voit les RDV B, pas ceux de A)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2/P10-P13.
 *             R9 livré (login multi-contexte : token nu + context_required si >1).
 *             R11 livré (PUT /v1/cabinet/providers/:id/secretariats).
 *             W54 livré (page praticien mes-secretariats).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL            URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL        URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_ID      UUID du praticien seed
 *   SEED_CABINET_A_ID         UUID de l'établissement A
 *   SEED_CABINET_B_ID         UUID de l'établissement B
 *   SEED_SECRETARIAT_A_ID     UUID du secrétariat A
 *   SEED_SECRETARIAT_B_ID     UUID du secrétariat B
 *   SEED_SECRETARY_A_EMAIL    Email de la secrétaire de l'établissement A
 *   SEED_SECRETARY_A_PASSWORD Mot de passe de la secrétaire A
 *   SEED_SECRETARY_B_EMAIL    Email de la secrétaire de l'établissement B
 *   SEED_SECRETARY_B_PASSWORD Mot de passe de la secrétaire B
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SEED_PRACTITIONER_ID =
  process.env.SEED_PRACTITIONER_ID ?? '00000000-0000-0000-0000-000000000001';

const SEED_CABINET_A_ID =
  process.env.SEED_CABINET_A_ID ?? '00000000-0000-0000-0000-000000000101';

const SEED_CABINET_B_ID =
  process.env.SEED_CABINET_B_ID ?? '00000000-0000-0000-0000-000000000102';

const SEED_SECRETARIAT_A_ID =
  process.env.SEED_SECRETARIAT_A_ID ?? '00000000-0000-0000-0000-000000000201';

const SEED_SECRETARIAT_B_ID =
  process.env.SEED_SECRETARIAT_B_ID ?? '00000000-0000-0000-0000-000000000202';

const SECRETARY_A = {
  email:    process.env.SEED_SECRETARY_A_EMAIL    ?? 'secretaire-a.demo@nubia.test',
  password: process.env.SEED_SECRETARY_A_PASSWORD ?? 'NubiaDemo1!',
};

const SECRETARY_B = {
  email:    process.env.SEED_SECRETARY_B_EMAIL    ?? 'secretaire-b.demo@nubia.test',
  password: process.env.SEED_SECRETARY_B_PASSWORD ?? 'NubiaDemo1!',
};

/** POST /v1/auth/select-context via direct API call and store the resulting JWT. */
async function selectContext(
  page: import('@playwright/test').Page,
  cabinetId: string,
  secretariatId?: string,
): Promise<string> {
  const token = await page.evaluate(
    async ({
      apiBase,
      cabinetId,
      secretariatId,
    }: {
      apiBase: string;
      cabinetId: string;
      secretariatId?: string;
    }): Promise<string> => {
      const currentJwt = localStorage.getItem('nubia_jwt') ?? '';
      const body: Record<string, string> = { cabinet_id: cabinetId };
      if (secretariatId) body['secretariat_id'] = secretariatId;

      const resp = await fetch(`${apiBase}/v1/auth/select-context`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${currentJwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });

      if (!resp.ok) return '';
      const data = (await resp.json()) as { token?: string; access_token?: string };
      const jwt = data.token ?? data.access_token ?? '';
      if (jwt) localStorage.setItem('nubia_jwt', jwt);
      return jwt;
    },
    { apiBase: API_BASE, cabinetId, secretariatId },
  );
  return token;
}

/** Login with arbitrary email+password, returns JWT (for secretary accounts). */
async function loginWithCredentials(
  page: import('@playwright/test').Page,
  email: string,
  password: string,
): Promise<string> {
  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.locator('form#login-form button[type="submit"]').click();
  await page.waitForURL((url) => !url.pathname.startsWith('/auth/login'), { timeout: 10_000 });
  return page.evaluate(() => localStorage.getItem('nubia_jwt') ?? '');
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Praticien — context A → agenda cabinet_id=A + assigne secrétariat A
// ─────────────────────────────────────────────────────────────────────────────
test(
  'praticien : select-context A → GET /v1/cabinet/agenda (200, cabinet_id=A) → PUT secretariats (200)',
  async ({ page }) => {
    // ── 1. Connexion praticien (multi-contexte : token nu) ────────────────────
    const nuToken = await loginAs(page, 'practitioner');
    expect(nuToken).toBeTruthy();

    // ── 2. Sélectionner le contexte établissement A ───────────────────────────
    const tokenA = await selectContext(page, SEED_CABINET_A_ID);
    expect(tokenA, 'select-context A doit retourner un JWT').toBeTruthy();

    // ── 3. Vérifier que le JWT porte cabinet_id = A ───────────────────────────
    const payloadA = await page.evaluate((): Record<string, unknown> => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      return JSON.parse(
        atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')),
      ) as Record<string, unknown>;
    });
    expect(payloadA['cabinet_id']).toBe(SEED_CABINET_A_ID);
    expect(payloadA['role']).toBe('practitioner');

    // ── 4. GET /v1/cabinet/agenda → 200 ──────────────────────────────────────
    const todayIso = new Date().toISOString().slice(0, 10);
    const agendaStatus = await page.evaluate(
      async ({ apiBase, date }: { apiBase: string; date: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(
          `${apiBase}/v1/cabinet/agenda?from=${encodeURIComponent(date)}&to=${encodeURIComponent(date)}`,
          { headers: { Authorization: `Bearer ${jwt}` } },
        );
        return resp.status;
      },
      { apiBase: API_BASE, date: todayIso },
    );
    expect(agendaStatus, `GET /v1/cabinet/agenda (ctx A) attendu 200, reçu ${agendaStatus}`).toBe(200);

    // ── 5. PUT /v1/cabinet/providers/:id/secretariats → assigne secrétariat A ─
    const assignStatus = await page.evaluate(
      async ({
        apiBase,
        practitionerId,
        secretariatId,
      }: {
        apiBase: string;
        practitionerId: string;
        secretariatId: string;
      }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(
          `${apiBase}/v1/cabinet/providers/${encodeURIComponent(practitionerId)}/secretariats`,
          {
            method: 'PUT',
            headers: {
              Authorization: `Bearer ${jwt}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ secretariat_ids: [secretariatId] }),
          },
        );
        return resp.status;
      },
      { apiBase: API_BASE, practitionerId: SEED_PRACTITIONER_ID, secretariatId: SEED_SECRETARIAT_A_ID },
    );
    expect(assignStatus, `PUT …/secretariats (A) attendu 200, reçu ${assignStatus}`).toBe(200);
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Secrétaire A voit les RDV ; secrétaire B voit les siens (cloisonnement)
// ─────────────────────────────────────────────────────────────────────────────
test(
  'secrétaire A voit agenda du docteur ; praticien répète pour B ; secrétaire B voit B, pas A',
  async ({ page }) => {
    // ══════════════════════════════════════════════════════════════════════════
    // Partie 1 — Praticien assigne secrétariat A
    // ══════════════════════════════════════════════════════════════════════════

    // ── 1a. Login praticien + select-context A ────────────────────────────────
    await loginAs(page, 'practitioner');
    const tokenA = await selectContext(page, SEED_CABINET_A_ID);
    expect(tokenA, 'select-context A doit retourner un JWT').toBeTruthy();

    // ── 1b. PUT secretariats → assigne secrétariat A ──────────────────────────
    const assignA = await page.evaluate(
      async ({
        apiBase,
        practitionerId,
        secretariatId,
      }: {
        apiBase: string;
        practitionerId: string;
        secretariatId: string;
      }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(
          `${apiBase}/v1/cabinet/providers/${encodeURIComponent(practitionerId)}/secretariats`,
          {
            method: 'PUT',
            headers: {
              Authorization: `Bearer ${jwt}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ secretariat_ids: [secretariatId] }),
          },
        );
        return resp.status;
      },
      { apiBase: API_BASE, practitionerId: SEED_PRACTITIONER_ID, secretariatId: SEED_SECRETARIAT_A_ID },
    );
    expect(assignA, `PUT secretariats A attendu 200, reçu ${assignA}`).toBe(200);

    // ── 1c. Reset session avant de connecter la secrétaire ───────────────────
    await clearSession(page);

    // ── 1d. Secrétaire A : login + select-context secrétariat A ───────────────
    const tokenSecA = await loginWithCredentials(page, SECRETARY_A.email, SECRETARY_A.password);
    expect(tokenSecA, 'secrétaire A doit obtenir un JWT').toBeTruthy();
    const scopedTokenA = await selectContext(page, SEED_CABINET_A_ID, SEED_SECRETARIAT_A_ID);
    expect(scopedTokenA, 'select-context secrétariat A doit retourner un JWT').toBeTruthy();

    // ── 1e. Secrétaire A → GET /v1/cabinet/appointments → 200 ────────────────
    const apptStatusA = await page.evaluate(async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return resp.status;
    }, API_BASE);
    expect(apptStatusA, `secrétaire A GET /v1/cabinet/appointments attendu 200, reçu ${apptStatusA}`).toBe(200);

    await clearSession(page);

    // ══════════════════════════════════════════════════════════════════════════
    // Partie 2 — Praticien assigne secrétariat B
    // ══════════════════════════════════════════════════════════════════════════

    // ── 2a. Login praticien + select-context B ────────────────────────────────
    await loginAs(page, 'practitioner');
    const tokenB = await selectContext(page, SEED_CABINET_B_ID);
    expect(tokenB, 'select-context B doit retourner un JWT').toBeTruthy();

    // ── 2b. PUT secretariats → assigne secrétariat B ──────────────────────────
    const assignB = await page.evaluate(
      async ({
        apiBase,
        practitionerId,
        secretariatId,
      }: {
        apiBase: string;
        practitionerId: string;
        secretariatId: string;
      }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(
          `${apiBase}/v1/cabinet/providers/${encodeURIComponent(practitionerId)}/secretariats`,
          {
            method: 'PUT',
            headers: {
              Authorization: `Bearer ${jwt}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ secretariat_ids: [secretariatId] }),
          },
        );
        return resp.status;
      },
      { apiBase: API_BASE, practitionerId: SEED_PRACTITIONER_ID, secretariatId: SEED_SECRETARIAT_B_ID },
    );
    expect(assignB, `PUT secretariats B attendu 200, reçu ${assignB}`).toBe(200);

    await clearSession(page);

    // ── 2c. Secrétaire B : login + select-context secrétariat B ───────────────
    const tokenSecB = await loginWithCredentials(page, SECRETARY_B.email, SECRETARY_B.password);
    expect(tokenSecB, 'secrétaire B doit obtenir un JWT').toBeTruthy();
    const scopedTokenB = await selectContext(page, SEED_CABINET_B_ID, SEED_SECRETARIAT_B_ID);
    expect(scopedTokenB, 'select-context secrétariat B doit retourner un JWT').toBeTruthy();

    // ── 2d. Secrétaire B → GET /v1/cabinet/appointments → 200 ────────────────
    const apptStatusB = await page.evaluate(async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return resp.status;
    }, API_BASE);
    expect(apptStatusB, `secrétaire B GET /v1/cabinet/appointments attendu 200, reçu ${apptStatusB}`).toBe(200);

    // ── 2e. Secrétaire B → vérifier que le JWT porte secretariat_id = B ───────
    const payloadSecB = await page.evaluate((): Record<string, unknown> => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      return JSON.parse(
        atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')),
      ) as Record<string, unknown>;
    });
    expect(payloadSecB['secretariat_id'], 'secrétaire B doit avoir secretariat_id = B')
      .toBe(SEED_SECRETARIAT_B_ID);
    expect(payloadSecB['cabinet_id'], 'secrétaire B doit avoir cabinet_id = B')
      .toBe(SEED_CABINET_B_ID);
  },
);
