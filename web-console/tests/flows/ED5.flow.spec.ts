/**
 * ED5 — Docteur multi-établissement (E2E flow)
 *
 * ⚠ ADAPTATION AU CONTRAT IMPLÉMENTÉ (2026-06-12, vérifié par curl) :
 *   Le parcours initial faisait faire au PRATICIEN des
 *   `PUT /v1/cabinet/providers/:id/secretariats → 200`. C'est contraire au
 *   contrat R11 (docs/12 §back-office) : cette route est réservée aux rôles
 *   admin/manager (`ProAdminOrManagerClaims`) → praticien = 403, et `:id` doit
 *   être un provider du cabinet du JWT (le cabinet Annecy n'a aucun provider →
 *   404 même pour un manager). Le flow est donc réécrit :
 *     - le praticien tente le PUT → 403 attendu (vérifie l'interdiction R11) ;
 *     - l'assignation au secrétariat A est faite par l'admin du cabinet Lyon ;
 *     - pour l'établissement B (Annecy, sans providers/patients), on vérifie
 *       l'observable : JWT cabinet_id=B, agenda 200 vide, secrétaire Annecy
 *       scopée (cabinet=B, secretariat=29870000-…) et appointments 200 (vide).
 *
 * Parcours :
 *   1. Login praticien multi-cabinet → context_required → select-context (A)
 *              → JWT cabinet_id=A, role=practitioner → GET /v1/cabinet/agenda → 200
 *              → PUT …/secretariats en tant que praticien → 403 (R11)
 *              → PUT …/secretariats en tant qu'admin Lyon → 200
 *   2. Admin assigne le provider au secrétariat A → secrétaire A voit les RDV
 *              (GET /v1/cabinet/appointments → 200, non vide) ;
 *      praticien select-context B → JWT cabinet_id=B → agenda 200 (praticiens vides) ;
 *      PUT praticien en contexte B → 403 ;
 *      secrétaire Annecy → JWT cabinet=B + secretariat=B → appointments 200 (vide).
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed
 *             seed.sql + seed_e2e.sql. R9 livré (login multi-contexte) ;
 *             R11 livré (PUT providers/:id/secretariats, admin/manager only).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL            URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL        URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_EMAIL   Email praticien multi-cabinet (praticien-multi.demo@nubia.test)
 *   SEED_PRACTITIONER_ID      UUID du PROVIDER du praticien (table provider, f…f1)
 *   SEED_CABINET_A_ID         UUID de l'établissement A (Lyon)
 *   SEED_CABINET_B_ID         UUID de l'établissement B (Annecy)
 *   SEED_SECRETARIAT_A_ID     UUID du secrétariat A (Lyon A)
 *   SEED_SECRETARIAT_B_ID     UUID du secrétariat B (Annecy)
 *   SEED_SECRETARY_A_EMAIL    Email de la secrétaire de l'établissement A
 *   SEED_SECRETARY_A_PASSWORD Mot de passe de la secrétaire A
 *   SEED_SECRETARY_B_EMAIL    Email de la secrétaire de l'établissement B (Annecy)
 *   SEED_SECRETARY_B_PASSWORD Mot de passe de la secrétaire B
 *   SEED_ADMIN_A_EMAIL        Email de l'admin du cabinet A (admin@cabinet-lyon.test)
 *   SEED_ADMIN_A_PASSWORD     Mot de passe de l'admin A (Nubia2026!)
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
  email:    process.env.SEED_SECRETARY_B_EMAIL    ?? 'secretaire-annecy.demo@nubia.test',
  password: process.env.SEED_SECRETARY_B_PASSWORD ?? 'NubiaDemo1!',
};

const ADMIN_A = {
  email:    process.env.SEED_ADMIN_A_EMAIL    ?? 'admin@cabinet-lyon.test',
  password: process.env.SEED_ADMIN_A_PASSWORD ?? 'Nubia2026!',
};

/**
 * Login direct API (sans UI) — retourne le token scopé (compte mono-contexte).
 * Utilisé pour l'admin du cabinet A (R11 : seul admin/manager peut assigner
 * un provider à un secrétariat).
 */
async function apiLogin(
  page: import('@playwright/test').Page,
  email: string,
  password: string,
): Promise<string> {
  const resp = await page.request.post(`${API_BASE}/v1/auth/login`, {
    data: { email, password },
  });
  if (!resp.ok()) return '';
  const data = (await resp.json()) as { access_token?: string };
  return data.access_token ?? '';
}

/** PUT /v1/cabinet/providers/:id/secretariats avec un token donné → status HTTP. */
async function putProviderSecretariats(
  page: import('@playwright/test').Page,
  token: string,
  providerId: string,
  secretariatIds: string[],
): Promise<number> {
  const resp = await page.request.put(
    `${API_BASE}/v1/cabinet/providers/${encodeURIComponent(providerId)}/secretariats`,
    {
      headers: { Authorization: `Bearer ${token}` },
      data: { secretariat_ids: secretariatIds },
    },
  );
  return resp.status();
}

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
  'praticien : select-context A → agenda 200 (cabinet_id=A) → PUT secretariats : 403 praticien / 200 admin (R11)',
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

    // ── 4. GET /v1/cabinet/agenda → 200 (contrat : params view/date) ─────────
    const todayIso = new Date().toISOString().slice(0, 10);
    const agendaStatus = await page.evaluate(
      async ({ apiBase, date }: { apiBase: string; date: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(
          `${apiBase}/v1/cabinet/agenda?view=day&date=${encodeURIComponent(date)}`,
          { headers: { Authorization: `Bearer ${jwt}` } },
        );
        return resp.status;
      },
      { apiBase: API_BASE, date: todayIso },
    );
    expect(agendaStatus, `GET /v1/cabinet/agenda (ctx A) attendu 200, reçu ${agendaStatus}`).toBe(200);

    // ── 5. PUT …/secretariats en tant que PRATICIEN → 403 (R11) ──────────────
    //    Contrat R11 (docs/12 §back-office) : assignation réservée admin/manager.
    const practitionerPut = await putProviderSecretariats(
      page, tokenA, SEED_PRACTITIONER_ID, [SEED_SECRETARIAT_A_ID],
    );
    expect(
      practitionerPut,
      `PUT …/secretariats en praticien attendu 403 (R11 admin/manager only), reçu ${practitionerPut}`,
    ).toBe(403);

    // ── 6. PUT …/secretariats en tant qu'ADMIN du cabinet A → 200 ────────────
    const adminToken = await apiLogin(page, ADMIN_A.email, ADMIN_A.password);
    expect(adminToken, 'admin du cabinet A doit obtenir un JWT scopé').toBeTruthy();

    const adminPut = await putProviderSecretariats(
      page, adminToken, SEED_PRACTITIONER_ID, [SEED_SECRETARIAT_A_ID],
    );
    expect(adminPut, `PUT …/secretariats (admin, A) attendu 200, reçu ${adminPut}`).toBe(200);
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Secrétaire A voit les RDV ; secrétaire B voit les siens (cloisonnement)
// ─────────────────────────────────────────────────────────────────────────────
test(
  'admin assigne A → secrétaire A voit les RDV ; contexte B (Annecy) : agenda vide + secrétaire B scopée',
  async ({ page }) => {
    // ══════════════════════════════════════════════════════════════════════════
    // Partie 1 — Assignation secrétariat A (par l'ADMIN, contrat R11) puis
    //            vérification côté secrétaire A.
    // ══════════════════════════════════════════════════════════════════════════

    // ── 1a. Login praticien + select-context A (sanity du parcours docteur) ───
    await loginAs(page, 'practitioner');
    const tokenA = await selectContext(page, SEED_CABINET_A_ID);
    expect(tokenA, 'select-context A doit retourner un JWT').toBeTruthy();

    // ── 1b. ADAPTÉ R11 : le praticien ne peut pas s'auto-assigner (403) ;
    //        c'est l'admin du cabinet A qui assigne le provider au secrétariat A.
    const adminToken = await apiLogin(page, ADMIN_A.email, ADMIN_A.password);
    expect(adminToken, 'admin du cabinet A doit obtenir un JWT scopé').toBeTruthy();

    const assignA = await putProviderSecretariats(
      page, adminToken, SEED_PRACTITIONER_ID, [SEED_SECRETARIAT_A_ID],
    );
    expect(assignA, `PUT secretariats A (admin) attendu 200, reçu ${assignA}`).toBe(200);

    // ── 1c. Reset session avant de connecter la secrétaire ───────────────────
    await clearSession(page);

    // ── 1d. Secrétaire A : login + select-context secrétariat A ───────────────
    const tokenSecA = await loginWithCredentials(page, SECRETARY_A.email, SECRETARY_A.password);
    expect(tokenSecA, 'secrétaire A doit obtenir un JWT').toBeTruthy();
    const scopedTokenA = await selectContext(page, SEED_CABINET_A_ID, SEED_SECRETARIAT_A_ID);
    expect(scopedTokenA, 'select-context secrétariat A doit retourner un JWT').toBeTruthy();

    // ── 1e. Secrétaire A → GET /v1/cabinet/appointments → 200, RDV visibles ──
    //    Contrat : réponse { data: [...] } ; le scoping secrétaire ne montre que
    //    les RDV des praticiens assignés au secrétariat A (provider du docteur).
    const apptA = await page.evaluate(async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const body = resp.ok ? (await resp.json()) as { data?: unknown[] } : {};
      return { status: resp.status, count: (body.data ?? []).length };
    }, API_BASE);
    expect(apptA.status, `secrétaire A GET /v1/cabinet/appointments attendu 200, reçu ${apptA.status}`).toBe(200);
    expect(
      apptA.count,
      'secrétaire A doit voir les RDV du docteur (provider assigné au secrétariat A)',
    ).toBeGreaterThan(0);

    await clearSession(page);

    // ══════════════════════════════════════════════════════════════════════════
    // Partie 2 — Établissement B (Annecy) : cabinet sans providers/patients.
    //   ADAPTÉ : pas de PUT possible en contexte B (le provider f…f1 appartient
    //   au cabinet A → 404, et le praticien est de toute façon 403 par R11).
    //   On vérifie l'observable du multi-établissement.
    // ══════════════════════════════════════════════════════════════════════════

    // ── 2a. Login praticien + select-context B → JWT cabinet_id = B ──────────
    await loginAs(page, 'practitioner');
    const tokenB = await selectContext(page, SEED_CABINET_B_ID);
    expect(tokenB, 'select-context B doit retourner un JWT').toBeTruthy();

    const payloadB = await page.evaluate((): Record<string, unknown> => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      return JSON.parse(
        atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')),
      ) as Record<string, unknown>;
    });
    expect(payloadB['cabinet_id'], 'JWT contexte B doit porter cabinet_id = B').toBe(SEED_CABINET_B_ID);
    expect(payloadB['role']).toBe('practitioner');

    // ── 2b. Agenda contexte B → 200 avec praticiens vides (cabinet sans providers)
    const todayIso = new Date().toISOString().slice(0, 10);
    const agendaB = await page.evaluate(
      async ({ apiBase, date }: { apiBase: string; date: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(
          `${apiBase}/v1/cabinet/agenda?view=day&date=${encodeURIComponent(date)}`,
          { headers: { Authorization: `Bearer ${jwt}` } },
        );
        const body = resp.ok
          ? (await resp.json()) as { practitioners?: unknown[]; slots?: unknown[] }
          : {};
        return {
          status: resp.status,
          practitionerCount: (body.practitioners ?? []).length,
          slotCount: (body.slots ?? []).length,
        };
      },
      { apiBase: API_BASE, date: todayIso },
    );
    expect(agendaB.status, `GET /v1/cabinet/agenda (ctx B) attendu 200, reçu ${agendaB.status}`).toBe(200);
    expect(
      agendaB.practitionerCount,
      'cabinet Annecy sans providers : agenda B doit lister 0 praticien',
    ).toBe(0);
    expect(agendaB.slotCount, 'cabinet Annecy : agenda B doit lister 0 créneau').toBe(0);

    // ── 2c. PUT en contexte B par le praticien → 403 (R11, jamais 200) ────────
    const putBStatus = await putProviderSecretariats(
      page, tokenB, SEED_PRACTITIONER_ID, [SEED_SECRETARIAT_B_ID],
    );
    expect(
      putBStatus,
      `PUT …/secretariats en praticien (ctx B) attendu 403 (R11), reçu ${putBStatus}`,
    ).toBe(403);

    await clearSession(page);

    // ── 2d. Secrétaire B (Annecy) : login + select-context secrétariat B ──────
    const tokenSecB = await loginWithCredentials(page, SECRETARY_B.email, SECRETARY_B.password);
    expect(tokenSecB, 'secrétaire B doit obtenir un JWT').toBeTruthy();
    const scopedTokenB = await selectContext(page, SEED_CABINET_B_ID, SEED_SECRETARIAT_B_ID);
    expect(scopedTokenB, 'select-context secrétariat B doit retourner un JWT').toBeTruthy();

    // ── 2e. Secrétaire B → JWT scopé cabinet B + secrétariat B ────────────────
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

    // ── 2f. Secrétaire B → GET /v1/cabinet/appointments → 200, vide ──────────
    //    Cloisonnement multi-établissement : aucun RDV du cabinet A ne fuit.
    const apptB = await page.evaluate(async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const body = resp.ok ? (await resp.json()) as { data?: unknown[] } : {};
      return { status: resp.status, count: (body.data ?? []).length };
    }, API_BASE);
    expect(apptB.status, `secrétaire B GET /v1/cabinet/appointments attendu 200, reçu ${apptB.status}`).toBe(200);
    expect(
      apptB.count,
      'cabinet Annecy sans patients : la secrétaire B ne doit voir aucun RDV (pas de fuite du cabinet A)',
    ).toBe(0);
  },
);
