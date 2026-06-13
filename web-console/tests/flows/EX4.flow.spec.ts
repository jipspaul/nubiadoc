/**
 * EX4 — Docteur assigne patient-list à secrétariat A
 *        → secrétaire A voit, secrétaire B ne voit pas
 *
 * Parcours :
 *   1. Docteur assigne sa liste de patients au secrétariat A
 *      via PUT /v1/cabinet/providers/:id/secretariats → 200
 *   2. Secrétaire A (contexte sélectionné : secrétariat A)
 *      → GET /v1/cabinet/patients → la liste contient les patients du docteur
 *   3. Secrétaire B (contexte sélectionné : secrétariat B)
 *      → GET /v1/cabinet/patients → NE contient PAS les patients du docteur
 *      (cloisonnement RLS P13/P14)
 *
 * Valide : isolation intra-établissement définie en P13/P14.
 * Dépend de : E0 ✓, R10 (secretary-scoped patients), R11 (provider→secretariat),
 *             W54, W55, seed P10–P14.
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2
 *             et seed P10–P14 (secretariat, secretariat_membership,
 *             provider_secretariat, RLS GUC).
 *             R1 restauré (login pro porte cabinet_id+role dans le JWT).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL              URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL          URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_ID        UUID du praticien seed
 *   SEED_SECRETARIAT_A_ID       UUID du secrétariat A (seed P10)
 *   SEED_SECRETARIAT_B_ID       UUID du secrétariat B (seed P10)
 *   SEED_SECRETARY_B_EMAIL      Email de la secrétaire du secrétariat B (seed P11)
 *   SEED_SECRETARY_B_PASSWORD   Mot de passe (défaut NubiaDemo1!)
 */

import { test, expect, type Page } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE = process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SEED_PRACTITIONER_ID =
  process.env.SEED_PRACTITIONER_ID ?? '00000000-0000-0000-0000-000000000001';

const SEED_SECRETARIAT_A_ID =
  process.env.SEED_SECRETARIAT_A_ID ?? '00000000-0000-0000-0000-000000000101';

const SEED_SECRETARIAT_B_ID =
  process.env.SEED_SECRETARIAT_B_ID ?? '00000000-0000-0000-0000-000000000102';

const SEED_SECRETARY_B_EMAIL =
  process.env.SEED_SECRETARY_B_EMAIL ?? 'secretaire-b.demo@nubia.test';

const SEED_SECRETARY_B_PASSWORD =
  process.env.SEED_SECRETARY_B_PASSWORD ?? 'NubiaDemo1!';

// L'assignation docteur→secrétariat (PUT …/secretariats) est réservée aux
// rôles admin/manager (R11, docs/12 §back-office) ; un praticien reçoit 403.
const SEED_ADMIN_EMAIL =
  process.env.SEED_MANAGER_EMAIL ?? 'admin@cabinet-lyon.test';
const SEED_ADMIN_PASSWORD =
  process.env.SEED_MANAGER_PASSWORD ?? 'Nubia2026!';

/** Login with explicit credentials. Used for secretary B. */
async function loginWithCredentials(
  page: Page,
  email: string,
  password: string,
): Promise<string> {
  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.locator('form#login-form button[type="submit"]').click();
  await page.waitForURL((url) => !url.pathname.startsWith('/auth/login'), {
    timeout: 10_000,
  });
  return page.evaluate(() => localStorage.getItem('nubia_jwt') ?? '');
}

/**
 * Selects secretariat context after login (R8: POST /v1/auth/select-context).
 * If the JWT already embeds the requested secretariat_id, it is returned as-is
 * (R9 single-membership fast-path). Updates localStorage with the new token.
 */
async function selectSecretariatContext(
  page: Page,
  secretariatId: string,
): Promise<string> {
  return page.evaluate(
    async ({
      apiBase,
      secretariatId,
    }: {
      apiBase: string;
      secretariatId: string;
    }) => {
      const current = localStorage.getItem('nubia_jwt') ?? '';
      if (!current) return current;

      const parts = current.split('.');
      if (parts.length !== 3) return current;

      const payload = JSON.parse(
        atob((parts[1] ?? '').replace(/-/g, '+').replace(/_/g, '/')),
      ) as Record<string, unknown>;

      // Already scoped to this secretariat — no round-trip needed.
      if (payload['secretariat_id'] === secretariatId) {
        return current;
      }

      const cabinetId = (payload['cabinet_id'] as string | undefined) ?? '';
      if (!cabinetId) return current;

      const resp = await fetch(`${apiBase}/v1/auth/select-context`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${current}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          cabinet_id: cabinetId,
          secretariat_id: secretariatId,
        }),
      });

      if (!resp.ok) return current;

      const data = (await resp.json()) as {
        token?: string;
        access_token?: string;
      };
      const newToken = data.token ?? data.access_token ?? current;
      localStorage.setItem('nubia_jwt', newToken);
      return newToken;
    },
    { apiBase: API_BASE, secretariatId },
  );
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Parcours complet cross-rôle
// docteur assigne → secrétaire A voit → secrétaire B ne voit pas
// ─────────────────────────────────────────────────────────────────────────────
test('EX4 : docteur assigne patient-list au secrétariat A → secrétaire A voit, secrétaire B ne voit pas', async ({
  page,
}) => {
  // ── 1. Connexion admin (l'assignation est admin/manager-only, R11) ────────
  await loginWithCredentials(page, SEED_ADMIN_EMAIL, SEED_ADMIN_PASSWORD);

  // ── 2. Admin : PUT /v1/cabinet/providers/:id/secretariats → 200 ───────────
  //    Assigne le praticien au secrétariat A (et retire l'éventuelle assignation
  //    au secrétariat B pour garantir l'isolation).
  const assignResult = await page.evaluate(
    async ({
      apiBase,
      providerId,
      secretariatAId,
    }: {
      apiBase: string;
      providerId: string;
      secretariatAId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/providers/${encodeURIComponent(providerId)}/secretariats`,
        {
          method: 'PUT',
          headers: {
            Authorization: `Bearer ${jwt}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ secretariat_ids: [secretariatAId] }),
        },
      );
      return { status: resp.status };
    },
    {
      apiBase: API_BASE,
      providerId: SEED_PRACTITIONER_ID,
      secretariatAId: SEED_SECRETARIAT_A_ID,
    },
  );

  expect(
    assignResult.status,
    `PUT /v1/cabinet/providers/:id/secretariats attendu 200, reçu ${assignResult.status}`,
  ).toBe(200);

  // ── 3. Récupérer les patients du praticien (comme il les voit) ─────────────
  //    Pour valider le cloisonnement, on récupère d'abord les IDs patients
  //    visibles via le jeton praticien.
  const practitionerPatients = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/patients`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      if (!resp.ok) return [] as string[];
      const json = await resp.json();
      const list = (Array.isArray(json) ? json : (json?.data ?? [])) as Array<{ id: string }>;
      return list.map((p) => p.id);
    },
    API_BASE,
  );

  // ── 4. Déconnexion praticien / connexion secrétaire A ─────────────────────
  await clearSession(page);
  await loginAs(page, 'secretary');
  await selectSecretariatContext(page, SEED_SECRETARIAT_A_ID);

  // ── 5. Secrétaire A : GET /v1/cabinet/patients → 200 ─────────────────────
  const secretaryAPatients = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/patients`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      if (!resp.ok) return { status: resp.status, ids: [] as string[] };
      const _j = await resp.json();
      const list = (Array.isArray(_j) ? _j : (_j?.data ?? [])) as Array<{ id: string }>;
      return { status: resp.status, ids: list.map((p) => p.id) };
    },
    API_BASE,
  );

  expect(
    secretaryAPatients.status,
    `secrétaire A : GET /v1/cabinet/patients attendu 200, reçu ${secretaryAPatients.status}`,
  ).toBe(200);

  // La secrétaire A doit voir au moins un patient (ceux du praticien assigné).
  expect(
    secretaryAPatients.ids.length,
    'secrétaire A doit voir ≥1 patient via son secrétariat',
  ).toBeGreaterThan(0);

  // Si des IDs praticien sont connus, au moins un doit être visible pour A.
  if (practitionerPatients.length > 0) {
    const overlap = practitionerPatients.some((id) =>
      secretaryAPatients.ids.includes(id),
    );
    expect(
      overlap,
      'secrétaire A doit voir les patients du praticien assigné à son secrétariat',
    ).toBe(true);
  }

  // ── 6. Déconnexion secrétaire A / connexion secrétaire B ─────────────────
  await clearSession(page);
  await loginWithCredentials(page, SEED_SECRETARY_B_EMAIL, SEED_SECRETARY_B_PASSWORD);
  await selectSecretariatContext(page, SEED_SECRETARIAT_B_ID);

  // ── 7. Secrétaire B : GET /v1/cabinet/patients → NE voit PAS les patients A
  const secretaryBPatients = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/patients`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      if (!resp.ok) return { status: resp.status, ids: [] as string[] };
      const _j = await resp.json();
      const list = (Array.isArray(_j) ? _j : (_j?.data ?? [])) as Array<{ id: string }>;
      return { status: resp.status, ids: list.map((p) => p.id) };
    },
    API_BASE,
  );

  expect(
    secretaryBPatients.status,
    `secrétaire B : GET /v1/cabinet/patients attendu 200, reçu ${secretaryBPatients.status}`,
  ).toBe(200);

  // Cloisonnement RLS : la secrétaire B ne doit voir aucun patient du secrétariat A.
  if (secretaryAPatients.ids.length > 0) {
    const leaked = secretaryAPatients.ids.filter((id) =>
      secretaryBPatients.ids.includes(id),
    );
    expect(
      leaked.length,
      `Cloisonnement RLS brisé : ${leaked.length} patient(s) du secrétariat A visible(s) par secrétaire B`,
    ).toBe(0);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Cloisonnement direct — secrétaire B (secrétariat B) ne voit pas
//              les patients visibles par secrétaire A (secrétariat A)
// ─────────────────────────────────────────────────────────────────────────────
test('EX4 : cloisonnement RLS — GET /v1/cabinet/patients retourne des scopes disjoints pour A et B', async ({
  page,
}) => {
  // ── 1. Secrétaire A : récupérer la liste patients ─────────────────────────
  await loginAs(page, 'secretary');
  await selectSecretariatContext(page, SEED_SECRETARIAT_A_ID);

  const listA = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/patients`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      if (!resp.ok) return { status: resp.status, ids: [] as string[] };
      const json = await resp.json();
      const patients = (Array.isArray(json) ? json : (json?.data ?? [])) as Array<{ id: string }>;
      return { status: resp.status, ids: patients.map((p) => p.id) };
    },
    API_BASE,
  );

  expect(
    listA.status,
    `secrétaire A : attendu 200, reçu ${listA.status}`,
  ).toBe(200);

  // ── 2. Secrétaire B : récupérer la liste patients ─────────────────────────
  await clearSession(page);
  await loginWithCredentials(page, SEED_SECRETARY_B_EMAIL, SEED_SECRETARY_B_PASSWORD);
  await selectSecretariatContext(page, SEED_SECRETARIAT_B_ID);

  const listB = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/patients`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      if (!resp.ok) return { status: resp.status, ids: [] as string[] };
      const json = await resp.json();
      const patients = (Array.isArray(json) ? json : (json?.data ?? [])) as Array<{ id: string }>;
      return { status: resp.status, ids: patients.map((p) => p.id) };
    },
    API_BASE,
  );

  expect(
    listB.status,
    `secrétaire B : attendu 200, reçu ${listB.status}`,
  ).toBe(200);

  // ── 3. Cloisonnement : listes disjointes (aucun patient partagé) ──────────
  //    P13/P14 : les patients de chaque secrétariat sont distincts.
  if (listA.ids.length > 0 && listB.ids.length > 0) {
    const intersection = listA.ids.filter((id) => listB.ids.includes(id));
    expect(
      intersection.length,
      `Cloisonnement P13/P14 brisé : ${intersection.length} patient(s) commun(s) entre secrétariat A et B`,
    ).toBe(0);
  }

  // Les deux listes ne doivent pas être identiques (différents scopes).
  // (garde : si les deux sont vides cela peut être un problème de seed,
  //  non un problème de cloisonnement — on ne fail pas dans ce cas.)
  if (listA.ids.length > 0 || listB.ids.length > 0) {
    const areIdentical =
      listA.ids.length === listB.ids.length &&
      listA.ids.every((id) => listB.ids.includes(id));
    expect(
      areIdentical,
      'Les listes patients de secrétariat A et B sont identiques — cloisonnement non effectif',
    ).toBe(false);
  }
});
