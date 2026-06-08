/**
 * E0 — Harnais parcours + fixtures (Playwright)
 *
 * Valide que l'infrastructure multi-rôle est opérationnelle :
 *   - loginAs('patient')  → token valide, GET /v1/me → 200
 *   - loginAs('practitioner') → token avec cabinet_id + role:'practitioner',
 *                               GET /v1/cabinet/agenda → 200
 *   - Reset entre tests : deux parcours successifs ne partagent pas de state JWT
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL      URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL  URL de l'API backend (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE = process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Patient : loginAs retourne un token valide + GET /v1/me → 200
// ─────────────────────────────────────────────────────────────────────────────
test('loginAs(patient) → token valide + GET /v1/me → 200', async ({ page }) => {
  const token = await loginAs(page, 'patient');

  expect(token).toBeTruthy();

  const meStatus = await page.evaluate(
    async ({ apiBase, jwt }: { apiBase: string; jwt: string }) => {
      const resp = await fetch(`${apiBase}/v1/me`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return resp.status;
    },
    { apiBase: API_BASE, jwt: token },
  );

  expect(meStatus).toBe(200);
});

// ─────────────────────────────────────────────────────────────────────────────
// Praticien : token porte cabinet_id + role:'practitioner' + agenda → 200
// ─────────────────────────────────────────────────────────────────────────────
test('loginAs(practitioner) → token avec cabinet_id+role:practitioner + GET /v1/cabinet/agenda → 200', async ({ page }) => {
  const token = await loginAs(page, 'practitioner');

  expect(token).toBeTruthy();

  const todayIso = new Date().toISOString().slice(0, 10);

  const result = await page.evaluate(
    async ({
      apiBase,
      jwt,
      date,
    }: {
      apiBase: string;
      jwt: string;
      date: string;
    }) => {
      // Décoder le payload JWT (base64url)
      const payload = JSON.parse(
        atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')),
      ) as Record<string, unknown>;

      const agendaResp = await fetch(
        `${apiBase}/v1/cabinet/agenda?from=${encodeURIComponent(date)}&to=${encodeURIComponent(date)}`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );

      return {
        hasCabinetId: typeof payload['cabinet_id'] === 'string' && payload['cabinet_id'].length > 0,
        role: payload['role'] as string | undefined,
        agendaStatus: agendaResp.status,
      };
    },
    { apiBase: API_BASE, jwt: token, date: todayIso },
  );

  expect(result.hasCabinetId).toBe(true);
  expect(result.role).toBe('practitioner');
  expect(result.agendaStatus).toBe(200);
});

// ─────────────────────────────────────────────────────────────────────────────
// Reset : deux parcours successifs ne partagent pas de state JWT
// ─────────────────────────────────────────────────────────────────────────────
test('reset entre tests : le JWT du parcours précédent est effacé', async ({ page }) => {
  // Simuler la fin d'un parcours précédent : poser un faux JWT en localStorage
  await page.goto('/');
  await page.evaluate(() => localStorage.setItem('nubia_jwt', 'stale-token-from-previous-flow'));

  // Appliquer le reset
  await clearSession(page);

  // Vérifier que le storage est vide
  const tokenAfterClear = await page.evaluate(() => localStorage.getItem('nubia_jwt'));
  expect(tokenAfterClear).toBeNull();
});
