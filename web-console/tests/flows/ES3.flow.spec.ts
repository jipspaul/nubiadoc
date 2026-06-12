/**
 * ES3 — Parcours secrétaire Équipe + cabinet + facturation (E2E flow)
 *
 * Valide les droits admin de la secrétaire sur l'équipe, les réglages cabinet
 * et la facturation (vue cabinet).
 *
 * Scénarios :
 *   1. gestion des membres (contrat réel api/src/auth/mod.rs : admin uniquement) :
 *      - secrétaire → POST /v1/cabinet/members → 403 (RBAC)
 *      - admin → inviter membre (POST /v1/cabinet/members 201, body avec
 *        first_name/last_name obligatoires)
 *        → modifier rôle (PATCH /v1/cabinet/members/:user_id 200)
 *        → retirer membre (DELETE /v1/cabinet/members/:user_id 204)
 *   2. réglages cabinet : GET /v1/cabinet 200
 *   3. facturation : GET /v1/cabinet/quotes 200 (vue cabinet)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed réel.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL    URL de l'API backend (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

/** Génère un email unique par run pour éviter les collisions. */
function freshEmail(): string {
  return `es3.member.${Date.now()}@nubia.test`;
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Gestion des membres — secrétaire interdite (403),
//              admin : inviter → modifier → retirer
// ─────────────────────────────────────────────────────────────────────────────
test('membres : secrétaire → 403 ; admin : inviter (201) → modifier rôle (200) → retirer (204)', async ({ page }) => {
  const memberEmail = freshEmail();

  // ── 1. Connexion secrétaire : POST /v1/cabinet/members → 403 (RBAC admin) ──
  await loginAs(page, 'secretary');

  const secretaryInviteStatus = await page.evaluate(
    async ({ apiBase, email }: { apiBase: string; email: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/members`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          role: 'secretary',
          first_name: 'ES3',
          last_name: 'Membre',
        }),
      });
      return resp.status;
    },
    { apiBase: API_BASE, email: memberEmail },
  );

  expect(
    secretaryInviteStatus,
    `POST /v1/cabinet/members (secrétaire) attendu 403, reçu ${secretaryInviteStatus}`,
  ).toBe(403);

  // ── 2. Connexion admin (manager) — seul rôle autorisé sur /members ────────
  await clearSession(page);
  await loginAs(page, 'manager');

  // ── 3. Inviter un membre via l'API (POST /v1/cabinet/members → 201) ───────
  const { inviteStatus, userId } = await page.evaluate(
    async ({ apiBase, email }: { apiBase: string; email: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/members`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          role: 'secretary',
          first_name: 'ES3',
          last_name: 'Membre',
        }),
      });
      const data = resp.ok
        ? ((await resp.json()) as { user_id?: string })
        : { user_id: undefined };
      return { inviteStatus: resp.status, userId: data.user_id ?? '' };
    },
    { apiBase: API_BASE, email: memberEmail },
  );

  expect(inviteStatus, `POST /v1/cabinet/members attendu 201, reçu ${inviteStatus}`).toBe(201);
  expect(userId).toBeTruthy();

  // ── 4. Modifier le rôle du membre (PATCH /v1/cabinet/members/:id → 200) ───
  const patchStatus = await page.evaluate(
    async ({ apiBase, uid }: { apiBase: string; uid: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/members/${uid}`, {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ role: 'practitioner' }),
      });
      return resp.status;
    },
    { apiBase: API_BASE, uid: userId },
  );

  expect(patchStatus, `PATCH /v1/cabinet/members/:id attendu 200, reçu ${patchStatus}`).toBe(200);

  // ── 5. Retirer le membre (DELETE /v1/cabinet/members/:id → 200 ou 204) ────
  const deleteStatus = await page.evaluate(
    async ({ apiBase, uid }: { apiBase: string; uid: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/members/${uid}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return resp.status;
    },
    { apiBase: API_BASE, uid: userId },
  );

  const deleteOk = deleteStatus === 200 || deleteStatus === 204;
  expect(deleteOk, `DELETE /v1/cabinet/members/:id attendu 200 ou 204, reçu ${deleteStatus}`).toBe(true);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Réglages cabinet (GET /v1/cabinet 200) + page /secretary/cabinet
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire : GET /v1/cabinet → 200 et page /secretary/cabinet visible', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Vérifier l'API directement ────────────────────────────────────────
  const cabinetStatus = await page.evaluate(async (apiBase: string) => {
    const jwt = localStorage.getItem('nubia_jwt') ?? '';
    const resp = await fetch(`${apiBase}/v1/cabinet`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    return resp.status;
  }, API_BASE);

  expect(cabinetStatus, `GET /v1/cabinet attendu 200, reçu ${cabinetStatus}`).toBe(200);

  // ── 3. La page /secretary/cabinet s'affiche ───────────────────────────────
  await page.goto('/secretary/cabinet');
  await expect(page.locator('h1')).toBeVisible({ timeout: 10_000 });
  await expect(page.locator('#settings-form')).toBeVisible({ timeout: 10_000 });
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 3 : Facturation — GET /v1/cabinet/quotes 200 (vue cabinet)
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire : GET /v1/cabinet/quotes → 200 et page /secretary/facturation visible', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Vérifier l'API directement ────────────────────────────────────────
  const quotesStatus = await page.evaluate(async (apiBase: string) => {
    const jwt = localStorage.getItem('nubia_jwt') ?? '';
    const resp = await fetch(`${apiBase}/v1/cabinet/quotes`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    return resp.status;
  }, API_BASE);

  expect(quotesStatus, `GET /v1/cabinet/quotes attendu 200, reçu ${quotesStatus}`).toBe(200);

  // ── 3. La page /secretary/facturation s'affiche ───────────────────────────
  await page.goto('/secretary/facturation');
  await expect(page.locator('h1')).toBeVisible({ timeout: 10_000 });
  // La table (données seed) ou le message vide doit devenir visible.
  // `:visible` + first() : les trois nœuds existent toujours dans le DOM
  // (strict mode violation sinon).
  await expect(
    page.locator('#quotes-table:visible, #quotes-empty:visible').first(),
  ).toBeVisible({ timeout: 10_000 });
});
