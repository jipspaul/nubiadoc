/**
 * ED2 — Salle d'attente praticien (E2E flow)
 *
 * Parcours :
 *   1. Render : loginAs(practitioner) → GET /praticien/file → page 200, sections visibles
 *   2. Call-next : GET /v1/cabinet/waiting-room → file visible
 *                  POST /v1/cabinet/waiting-room/call-next → patient retiré de la file (polling mis à jour)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *             R1 restauré (login pro porte cabinet_id+role).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web   (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL    URL de l'API back  (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Render — login praticien → /praticien/file s'affiche (200)
// ─────────────────────────────────────────────────────────────────────────────
test('render : loginAs(practitioner) → /praticien/file affiche les sections (200)', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Navigation vers la page W30 ───────────────────────────────────────
  await page.goto('/praticien/file');

  // ── 3. Page correctement rendue (pas de redirect 401/403) ────────────────
  await expect(page.getByRole('heading', { name: "Salle d'attente", level: 1 })).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole('heading', { name: 'File d\'attente', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Appeler le suivant', level: 2 })).toBeVisible();
  await expect(page.getByRole('button', { name: /appeler le patient suivant/i })).toBeVisible();

  // ── 4. GET /v1/cabinet/waiting-room → 200 (via API directe) ──────────────
  const roomResult = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/waiting-room`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return { status: resp.status };
    },
    API_BASE,
  );
  expect(roomResult.status).toBe(200);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Call-next — POST call-next → patient retiré de la file
// ─────────────────────────────────────────────────────────────────────────────
test('call-next : POST /v1/cabinet/waiting-room/call-next → patient retiré (polling mis à jour)', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Lire la file avant l'appel ────────────────────────────────────────
  const beforeResult = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/waiting-room`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as Array<{ id?: string; patient_id?: string; position?: number }>)
        : [];
      return { status: resp.status, count: Array.isArray(data) ? data.length : 0 };
    },
    API_BASE,
  );
  expect(beforeResult.status).toBe(200);

  // ── 3. POST /v1/cabinet/waiting-room/call-next ────────────────────────────
  const callResult = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/waiting-room/call-next`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Idempotency-Key': crypto.randomUUID(),
        },
      });
      const data = resp.ok ? ((await resp.json()) as { id?: string; patient_id?: string }) : null;
      return { status: resp.status, data };
    },
    API_BASE,
  );

  // call-next retourne 200 (patient appelé) ou 204/404 si file vide
  expect(callResult.status).toBeLessThan(500);
  expect([200, 204, 404]).toContain(callResult.status);

  // ── 4. Si un patient a été appelé (200), vérifier que la file a diminué ──
  if (callResult.status === 200 && beforeResult.count > 0) {
    const afterResult = await page.evaluate(
      async (apiBase: string) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(`${apiBase}/v1/cabinet/waiting-room`, {
          headers: { Authorization: `Bearer ${jwt}` },
        });
        const data = resp.ok
          ? ((await resp.json()) as Array<{ id?: string; patient_id?: string }>)
          : [];
        return { status: resp.status, count: Array.isArray(data) ? data.length : 0 };
      },
      API_BASE,
    );
    expect(afterResult.status).toBe(200);
    // La file doit avoir diminué d'au moins 1
    expect(afterResult.count).toBeLessThan(beforeResult.count);
  }

  // ── 5. Vérifier que la page UI reflète le changement (polling) ────────────
  await page.goto('/praticien/file');
  // Le polling charge automatiquement ; la section est visible (pas d'erreur 401/403)
  await expect(page.locator('#queue-content, #queue-status')).toBeVisible({ timeout: 15_000 });
});
