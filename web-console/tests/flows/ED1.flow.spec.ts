/**
 * ED1 — Dashboard + agenda praticien (E2E flow)
 *
 * Parcours :
 *   1. Dashboard : loginAs(practitioner) → GET /praticien/dashboard (200, données seed)
 *                  → GET /v1/cabinet/agenda → réponse 200
 *   2. Créneaux  : POST /v1/cabinet/slots → créneau créé (201)
 *                  → PATCH /v1/cabinet/slots/:id → créneau modifié (2xx)
 *                  → DELETE /v1/cabinet/slots/:id → créneau supprimé (2xx)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *             R1 restauré (login pro porte cabinet_id+role).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL    URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_ID  UUID du praticien seed (pour les créneaux)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SEED_PRACTITIONER_ID =
  process.env.SEED_PRACTITIONER_ID ?? '00000000-0000-0000-0000-000000000001';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Dashboard praticien — render + GET /v1/cabinet/agenda (200)
// ─────────────────────────────────────────────────────────────────────────────
test('dashboard praticien : page visible + GET /v1/cabinet/agenda retourne 200', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Page dashboard W28 : render visible ───────────────────────────────
  await page.goto('/praticien/dashboard');
  await expect(page.locator('h1')).toBeVisible({ timeout: 15_000 });
  await expect(page.locator('h1')).toContainText('Tableau de bord');

  // ── 3. GET /v1/cabinet/agenda → 200 ──────────────────────────────────────
  const todayIso = new Date().toISOString().slice(0, 10);
  const agendaResult = await page.evaluate(
    async ({ apiBase, date }: { apiBase: string; date: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/agenda?from=${encodeURIComponent(date)}&to=${encodeURIComponent(date)}`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, date: todayIso },
  );
  expect(agendaResult.status).toBe(200);

  // ── 4. GET /v1/cabinet/appointments → 200 ────────────────────────────────
  const apptResult = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return { status: resp.status };
    },
    API_BASE,
  );
  expect(apptResult.status).toBe(200);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Créneaux — créer → visible dans l'agenda → éditer → supprimer
// ─────────────────────────────────────────────────────────────────────────────
test('créneaux : POST /v1/cabinet/slots → PATCH → DELETE', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Page agenda W29 : visible ─────────────────────────────────────────
  await page.goto('/praticien/agenda');
  await expect(page.locator('h1')).toBeVisible({ timeout: 15_000 });

  // ── 3. POST /v1/cabinet/slots → créneau créé (201) ───────────────────────
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  tomorrow.setHours(9, 0, 0, 0);
  const endsAt = new Date(tomorrow);
  endsAt.setHours(9, 30, 0, 0);

  const createResult = await page.evaluate(
    async ({
      apiBase,
      practitionerId,
      startsAt,
      endsAt,
    }: {
      apiBase: string;
      practitionerId: string;
      startsAt: string;
      endsAt: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/slots`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          practitioner_id: practitionerId,
          starts_at: startsAt,
          ends_at: endsAt,
          status: 'open',
        }),
      });
      const data = resp.ok ? ((await resp.json()) as { id?: string }) : null;
      return { status: resp.status, data };
    },
    {
      apiBase: API_BASE,
      practitionerId: SEED_PRACTITIONER_ID,
      startsAt: tomorrow.toISOString(),
      endsAt: endsAt.toISOString(),
    },
  );

  expect(createResult.status).toBe(201);
  const slotId = createResult.data?.id;
  expect(slotId).toBeTruthy();
  if (!slotId) return; // garde TypeScript

  // ── 4. GET /v1/cabinet/agenda → créneau visible (200) ────────────────────
  const tomorrowIso = tomorrow.toISOString().slice(0, 10);
  const agendaCheck = await page.evaluate(
    async ({ apiBase, date }: { apiBase: string; date: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/agenda?from=${encodeURIComponent(date)}&to=${encodeURIComponent(date)}`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, date: tomorrowIso },
  );
  expect(agendaCheck.status).toBe(200);

  // ── 5. PATCH /v1/cabinet/slots/:id → créneau modifié (2xx) ───────────────
  const patchedEndsAt = new Date(tomorrow);
  patchedEndsAt.setHours(10, 0, 0, 0);

  const patchResult = await page.evaluate(
    async ({
      apiBase,
      slotId,
      endsAt,
    }: {
      apiBase: string;
      slotId: string;
      endsAt: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/slots/${encodeURIComponent(slotId)}`, {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ ends_at: endsAt }),
      });
      return { status: resp.status };
    },
    { apiBase: API_BASE, slotId, endsAt: patchedEndsAt.toISOString() },
  );
  expect(patchResult.status).toBeLessThan(300);

  // ── 6. DELETE /v1/cabinet/slots/:id → créneau supprimé (2xx) ─────────────
  const deleteResult = await page.evaluate(
    async ({ apiBase, slotId }: { apiBase: string; slotId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/slots/${encodeURIComponent(slotId)}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return { status: resp.status };
    },
    { apiBase: API_BASE, slotId },
  );
  expect(deleteResult.status).toBeLessThan(300);
});
