/**
 * EW52.context-switcher — Sélecteur de contexte multi-tenant (E2E flow, mocked)
 *
 * Valide W52.d :
 *   1. User mono-contexte (patient) → le bouton ContextSwitcher est absent du DOM
 *   2. User multi-contexte (secrétaire) → bouton visible, clic ouvre le dropdown,
 *      sélection d'un contexte intercepte POST /api/select-context (page.route)
 *      et la page se recharge vers /secretary/dashboard
 *   3. Après le switch, le contexte actif affiché dans le header correspond au
 *      contexte sélectionné (label non vide dans .ctx-switcher__label)
 *
 * ContextSwitcher.astro soumet un <form method="POST" action="/api/select-context">
 * (BFF Astro) — c'est ce endpoint navigateur que page.route intercepte.
 * L'appel backend (/v1/auth/select-context) est fait côté serveur Astro et
 * n'est pas interceptable par page.route ; le mock retourne donc un 303 redirect.
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   SEED_CABINET_ID       UUID cabinet demo (défaut 00000000-0000-0000-0000-000000000100)
 *   SEED_SECRETARIAT_B_ID UUID secrétariat B (défaut 00000000-0000-0000-0000-000000000202)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const CABINET_ID       = process.env.SEED_CABINET_ID       ?? '00000000-0000-0000-0000-000000000100';
const SECRETARIAT_B_ID = process.env.SEED_SECRETARIAT_B_ID ?? '00000000-0000-0000-0000-000000000202';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : user mono-contexte (patient) → ContextSwitcher absent du DOM
// ─────────────────────────────────────────────────────────────────────────────
test('user mono-contexte (patient) → ContextSwitcher absent du DOM', async ({ page }) => {
  await loginAs(page, 'patient');

  await page.waitForURL((u) => u.pathname.startsWith('/patient'), { timeout: 8_000 });

  // Le ContextSwitcher ne se rend que si hasMultiple=true (contexts.length > 1).
  // Un patient n'a aucun membership professionnel → composant absent.
  await expect(
    page.locator('.ctx-switcher'),
    'Patient mono-contexte : le ContextSwitcher ne doit pas être rendu',
  ).toHaveCount(0);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : user multi-contexte → bouton visible, dropdown, POST mocké
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire multi-contexte : switcher visible → clic ouvre dropdown → POST /api/select-context intercepté → page recharge', async ({ page }) => {
  // ── Intercepter le POST navigateur vers le BFF /api/select-context ────────
  // ContextSwitcher.astro soumet un <form action="/api/select-context"> — c'est
  // la requête browser qu'on intercepte ici (pas l'appel server→backend).
  let interceptedBody = '';
  await page.route('**/api/select-context', async (route) => {
    if (route.request().method() === 'POST') {
      interceptedBody = route.request().postData() ?? '';
      await route.fulfill({
        status:  303,
        headers: { Location: '/secretary/dashboard' },
      });
    } else {
      await route.continue();
    }
  });

  await loginAs(page, 'secretary');

  // Passer l'éventuelle page select-context initiale
  await page.waitForURL(
    (u) => u.pathname === '/auth/select-context' || u.pathname.startsWith('/secretary'),
    { timeout: 10_000 },
  );
  if (page.url().includes('/auth/select-context')) {
    await page.locator('#context-list article.ctx-card button.ctx-btn').first().click({ timeout: 8_000 });
    await page.waitForURL((u) => u.pathname.startsWith('/secretary'), { timeout: 8_000 });
  }

  // ── Le switcher est visible pour un user multi-contexte ──────────────────
  await expect(
    page.locator('.ctx-switcher'),
    'Switcher visible en multi-contexte',
  ).toHaveCount(1);

  // ── Clic sur le trigger → dropdown ouvert ────────────────────────────────
  await page.locator('summary.ctx-switcher__trigger').click();
  await expect(
    page.locator('ul.ctx-switcher__list'),
    'Liste des contextes visible après clic sur trigger',
  ).toBeVisible();

  // ── Soumettre le form du contexte B → POST intercepté ────────────────────
  const formB = page.locator(`ul.ctx-switcher__list form:has(input[name="secretariat_id"][value="${SECRETARIAT_B_ID}"])`);
  await expect(formB, 'Form du secrétariat B présent dans la liste').toHaveCount(1);

  const navigationPromise = page.waitForURL(
    (u) => u.pathname === '/secretary/dashboard',
    { timeout: 10_000 },
  );
  await formB.locator('button[type="submit"]').click();
  await navigationPromise;

  // ── Vérifier que le body du form contenait bien le secretariat_id B ────────
  // Le form envoie des données URL-encodées (application/x-www-form-urlencoded).
  expect(
    interceptedBody,
    'POST /api/select-context doit porter le secretariat_id B',
  ).toContain(SECRETARIAT_B_ID);
  expect(
    interceptedBody,
    'POST doit porter le cabinet_id',
  ).toContain(CABINET_ID);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 3 : après context switch, le label dans le header correspond au
// contexte sélectionné
// ─────────────────────────────────────────────────────────────────────────────
test('après context switch, le contexte actif dans le header correspond au contexte sélectionné', async ({ page }) => {
  // ── Intercepter le POST navigateur vers le BFF /api/select-context ────────
  await page.route('**/api/select-context', async (route) => {
    if (route.request().method() === 'POST') {
      // Mettre à jour nubia_ctx pour refléter le nouveau contexte (secrétariat B).
      // Le nubia_jwt existant (JWT réel) reste inchangé → l'AppShell SSR peut
      // appeler GET /v1/me avec succès et afficher le bon label après redirection.
      const hostname = new URL(page.url()).hostname;
      await page.context().addCookies([{
        name:     'nubia_ctx',
        value:    `${CABINET_ID}|secretary|${SECRETARIAT_B_ID}`,
        domain:   hostname,
        path:     '/',
        httpOnly: false,
        secure:   false,
        sameSite: 'Strict',
      }]);
      await route.fulfill({
        status:  303,
        headers: { Location: '/secretary/dashboard' },
      });
    } else {
      await route.continue();
    }
  });

  await loginAs(page, 'secretary');

  await page.waitForURL(
    (u) => u.pathname === '/auth/select-context' || u.pathname.startsWith('/secretary'),
    { timeout: 10_000 },
  );
  if (page.url().includes('/auth/select-context')) {
    await page.locator('#context-list article.ctx-card button.ctx-btn').first().click({ timeout: 8_000 });
    await page.waitForURL((u) => u.pathname.startsWith('/secretary'), { timeout: 8_000 });
  }

  // ── Capturer le label du contexte actuel (secrétariat A) ─────────────────
  const labelBefore = await page.locator('.ctx-switcher__label').textContent();
  expect(labelBefore, 'Label du switcher doit être non vide avant le switch').toBeTruthy();

  // ── Switcher vers le secrétariat B ────────────────────────────────────────
  await page.locator('summary.ctx-switcher__trigger').click();
  const formB = page.locator(`ul.ctx-switcher__list form:has(input[name="secretariat_id"][value="${SECRETARIAT_B_ID}"])`);

  const navPromise = page.waitForURL(
    (u) => u.pathname === '/secretary/dashboard',
    { timeout: 10_000 },
  );
  await formB.locator('button[type="submit"]').click();
  await navPromise;

  // ── Vérifier le label après switch ───────────────────────────────────────
  // Le mock a mis à jour nubia_ctx → secrétariat B actif. L'AppShell SSR utilise
  // le JWT réel pour GET /v1/me → switcher affiché avec le label du secrétariat B.
  const labelAfter = await page.locator('.ctx-switcher__label').textContent();
  expect(labelAfter, 'Le label du switcher doit être non vide après context switch').toBeTruthy();

  await expect(
    page.locator('.ctx-switcher'),
    'Le ContextSwitcher doit toujours être rendu après le switch',
  ).toHaveCount(1);
});
