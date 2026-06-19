/**
 * EW52.context-switcher — Sélecteur de contexte multi-tenant (E2E flow, mocked)
 *
 * Valide W52.d :
 *   1. User mono-contexte (patient) → le bouton ContextSwitcher est absent du DOM
 *   2. User multi-contexte (secrétaire) → bouton visible, clic ouvre le dropdown,
 *      sélection d'un contexte intercepte POST /v1/auth/select-context (page.route)
 *      et la page se recharge
 *   3. Après le switch, le ContextSwitcher est toujours rendu dans le header
 *      avec un label non vide
 *
 * ContextSwitcher.tsx (Preact, client:load dans AppShell) appelle directement
 * POST /v1/auth/select-context via apiFetch — c'est cet appel que page.route
 * intercepte. Le mock retourne un 200 JSON { access_token } pour éviter toute
 * mutation côté backend. Le JWT réel (obtenu via loginAs) est réutilisé comme
 * access_token factice afin que la page reste valide après window.location.reload().
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   SEED_CABINET_ID       UUID cabinet demo (défaut 00000000-0000-0000-0000-000000000100)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const CABINET_ID = process.env.SEED_CABINET_ID ?? '00000000-0000-0000-0000-000000000100';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : user mono-contexte (patient) → ContextSwitcher absent du DOM
// ─────────────────────────────────────────────────────────────────────────────
test('user mono-contexte (patient) → ContextSwitcher absent du DOM', async ({ page }) => {
  await loginAs(page, 'patient');

  await page.waitForURL((u) => u.pathname.startsWith('/patient'), { timeout: 8_000 });

  // Le ContextSwitcher.tsx retourne null si contexts.length <= 1.
  // Un patient n'a aucun membership professionnel → GET /v1/me retourne 0 contextes.
  // Attendre la fin des appels réseau (incluant getMe()) avant d'asserter l'absence.
  await page.waitForLoadState('networkidle', { timeout: 8_000 });
  await expect(
    page.locator('.ctx-switcher'),
    'Patient mono-contexte : le ContextSwitcher ne doit pas être rendu',
  ).toHaveCount(0);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : user multi-contexte → bouton visible, dropdown, POST mocké
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire multi-contexte : switcher visible → clic ouvre dropdown → POST /v1/auth/select-context intercepté → page recharge', async ({ page }) => {
  // ── Connexion secrétaire ─────────────────────────────────────────────────
  const realToken = await loginAs(page, 'secretary');

  // Passer l'éventuelle page select-context initiale (Astro form vers /api/select-context,
  // non affecté par notre route mock ciblant /v1/auth/select-context)
  await page.waitForURL(
    (u) => u.pathname === '/auth/select-context' || u.pathname.startsWith('/secretary'),
    { timeout: 10_000 },
  );
  if (page.url().includes('/auth/select-context')) {
    await page.locator('#context-list article.ctx-card button.ctx-btn').first().click({ timeout: 8_000 });
    await page.waitForURL((u) => u.pathname.startsWith('/secretary'), { timeout: 8_000 });
  }

  // ── Intercepter POST /v1/auth/select-context (appel direct du composant TSX) ──
  // ContextSwitcher.tsx → selectContext() → apiFetch('/v1/auth/select-context')
  // Le mock retourne le JWT réel (inchangé) pour maintenir une session valide après reload.
  let interceptedBody = '';
  await page.route('**/v1/auth/select-context', async (route) => {
    if (route.request().method() === 'POST') {
      interceptedBody = route.request().postData() ?? '';
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ access_token: realToken }),
      });
    } else {
      await route.continue();
    }
  });

  // ── Le switcher est visible une fois getMe() complété (secrétaire multi-contexte) ──
  await expect(
    page.locator('.ctx-switcher'),
    'Switcher visible en multi-contexte',
  ).toHaveCount(1, { timeout: 8_000 });

  // ── Clic sur le trigger (button) → dropdown ouvert ────────────────────────
  await page.locator('button.ctx-switcher__trigger').click();
  await expect(
    page.locator('ul.ctx-switcher__list'),
    'Liste des contextes visible après clic sur trigger',
  ).toBeVisible();

  // ── Clic sur la première option non-active → POST intercepté + reload ─────
  const nonActiveOption = page
    .locator('button.ctx-switcher__option:not(.ctx-switcher__option--current)')
    .first();
  await expect(nonActiveOption, 'Au moins une option non-active doit exister').toHaveCount(1);

  await Promise.all([
    page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 10_000 }),
    nonActiveOption.click(),
  ]);

  // ── Vérifier que le corps du POST contenait bien le cabinet_id ────────────
  expect(interceptedBody, 'Le corps du POST doit être non vide').toBeTruthy();
  const parsedBody = JSON.parse(interceptedBody) as { cabinet_id?: string; secretariat_id?: string };
  expect(
    parsedBody.cabinet_id,
    'POST /v1/auth/select-context doit porter le cabinet_id correct',
  ).toBe(CABINET_ID);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 3 : après context switch, le ContextSwitcher est rendu et le label
// dans le header est non vide
// ─────────────────────────────────────────────────────────────────────────────
test('après context switch, le ContextSwitcher est rendu et le label est non vide', async ({ page }) => {
  // ── Connexion secrétaire ─────────────────────────────────────────────────
  const realToken = await loginAs(page, 'secretary');

  await page.waitForURL(
    (u) => u.pathname === '/auth/select-context' || u.pathname.startsWith('/secretary'),
    { timeout: 10_000 },
  );
  if (page.url().includes('/auth/select-context')) {
    await page.locator('#context-list article.ctx-card button.ctx-btn').first().click({ timeout: 8_000 });
    await page.waitForURL((u) => u.pathname.startsWith('/secretary'), { timeout: 8_000 });
  }

  // ── Intercepter POST /v1/auth/select-context ──────────────────────────────
  // Le mock retourne le JWT réel → après reload, getMe() avec le même token
  // retourne les mêmes contextes → le switcher reste affiché.
  await page.route('**/v1/auth/select-context', async (route) => {
    if (route.request().method() === 'POST') {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ access_token: realToken }),
      });
    } else {
      await route.continue();
    }
  });

  // ── Attendre que le switcher soit visible ─────────────────────────────────
  await expect(page.locator('.ctx-switcher')).toHaveCount(1, { timeout: 8_000 });

  // ── Capturer le label du contexte actuel avant le switch ──────────────────
  const labelBefore = await page.locator('.ctx-switcher__label').textContent();
  expect(labelBefore, 'Label du switcher doit être non vide avant le switch').toBeTruthy();

  // ── Déclencher le switch ──────────────────────────────────────────────────
  await page.locator('button.ctx-switcher__trigger').click();
  const nonActiveOption = page
    .locator('button.ctx-switcher__option:not(.ctx-switcher__option--current)')
    .first();
  await expect(nonActiveOption).toHaveCount(1);

  await Promise.all([
    page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 10_000 }),
    nonActiveOption.click(),
  ]);

  // ── Vérifier le ContextSwitcher après switch ──────────────────────────────
  // Le mock a retourné le JWT réel → session toujours valide → getMe() → même
  // liste de contextes → switcher toujours rendu avec un label non vide.
  await expect(
    page.locator('.ctx-switcher'),
    'Le ContextSwitcher doit toujours être rendu après le switch',
  ).toHaveCount(1, { timeout: 8_000 });

  const labelAfter = await page.locator('.ctx-switcher__label').textContent();
  expect(labelAfter, 'Le label du switcher doit être non vide après context switch').toBeTruthy();
});
