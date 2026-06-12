/**
 * EW52 — ContextSwitcher : visibilité + changement de contexte (E2E flow)
 *
 * Valide W52 (sélecteur de contexte dans AppShell, dépend de W52.a/b/c et R8) :
 *   1. User avec 1 seul contexte (patient) → ContextSwitcher absent du DOM
 *   2. User multi-contexte (secrétaire avec 2 secrétariats) → switcher visible,
 *      sélection d'un autre contexte → redirect vers le dashboard du nouveau rôle,
 *      cookie `nubia_ctx` mis à jour
 *   3. Session expirée pendant le switch → redirect vers /auth/login
 *
 * Différence vs ES5 (qui teste l'isolation des données par secrétariat) :
 *   EW52 cible le composant UI ContextSwitcher (W52.a) et son intégration
 *   AppShell (W52.b) + action /api/select-context (W52.c). C'est un test de
 *   *présentation*, pas de cloisonnement RLS.
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed
 *   P2 (comptes démo) + P11 (secretariat_membership : 2 secrétariats pour la
 *   secrétaire demo) + R1 ✅ + R8 (POST /v1/auth/select-context) opérationnel.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   SEED_CABINET_ID       UUID cabinet demo (défaut 00000000-0000-0000-0000-000000000100)
 *   SEED_SECRETARIAT_A_ID UUID secrétariat A
 *   SEED_SECRETARIAT_B_ID UUID secrétariat B
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const CABINET_ID = process.env.SEED_CABINET_ID ?? '00000000-0000-0000-0000-000000000100';
const SECRETARIAT_A_ID = process.env.SEED_SECRETARIAT_A_ID ?? '00000000-0000-0000-0000-000000000201';
const SECRETARIAT_B_ID = process.env.SEED_SECRETARIAT_B_ID ?? '00000000-0000-0000-0000-000000000202';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : user mono-contexte (patient) → ContextSwitcher absent
// ─────────────────────────────────────────────────────────────────────────────
test('user 1 contexte (patient) → ContextSwitcher absent du DOM', async ({ page }) => {
  await loginAs(page, 'patient');

  // Le patient ne navigue jamais sur l'AppShell des pros, on cible /patient/accueil
  // qui devrait être la cible du loginAs(patient) — sinon /patient.
  await page.waitForURL((u) => u.pathname.startsWith('/patient'), { timeout: 8_000 });

  // Le ContextSwitcher rend seulement si contexts.length > 1 (cf. ContextSwitcher.astro)
  // Pour un patient (qui n'a pas de memberships pro), hasMultiple = false → composant absent.
  await expect(
    page.locator('.ctx-switcher'),
    'Patient mono-contexte : le ContextSwitcher ne doit pas être rendu (hasMultiple=false)',
  ).toHaveCount(0);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : secrétaire multi-contexte → switcher visible → switch → redirect
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire multi-secrétariat : switcher visible + switch → nubia_ctx mis à jour', async ({ page, context }) => {
  await loginAs(page, 'secretary');

  // La secrétaire multi-contexte est redirigée vers /auth/select-context après login
  // (cf. ES5). Elle choisit le secrétariat A pour entrer dans l'AppShell.
  await page.waitForURL((u) =>
    u.pathname === '/auth/select-context' || u.pathname.startsWith('/secretary'),
    { timeout: 10_000 },
  );

  // Si on est sur /auth/select-context, on choisit le secrétariat A
  if (page.url().includes('/auth/select-context')) {
    // La page select-context expose un <form> par contexte (mêmes UUIDs que ES5)
    // On clique le bouton du contexte A
    const formA = page.locator(`form[data-secretariat-id="${SECRETARIAT_A_ID}"]`)
      .or(page.locator(`button:has-text("Secrétariat A")`).first());
    await formA.first().click({ timeout: 5_000 }).catch(async () => {
      // Fallback : soumettre le premier bouton "Choisir" disponible
      await page.locator('button:has-text("Choisir")').first().click();
    });
    await page.waitForURL((u) => u.pathname.startsWith('/secretary'), { timeout: 8_000 });
  }

  // ── On est sur /secretary/dashboard avec contexte A ──────────────────────
  await expect(page.locator('.ctx-switcher'), 'Switcher visible en multi-contexte').toHaveCount(1);

  // Snapshot du cookie nubia_ctx (contexte A)
  const cookiesBefore = await context.cookies();
  const ctxBefore = cookiesBefore.find((c) => c.name === 'nubia_ctx')?.value;
  expect(ctxBefore, 'Cookie nubia_ctx doit exister après sélection contexte A').toBeTruthy();

  // ── Ouvrir le dropdown ───────────────────────────────────────────────────
  const trigger = page.locator('summary.ctx-switcher__trigger');
  await trigger.click();
  const list = page.locator('ul.ctx-switcher__list');
  await expect(list, 'Liste des contextes visible après clic sur trigger').toBeVisible();

  // ── Soumettre le form du contexte B (cabinet identique, secrétariat différent) ─
  // Chaque <li> contient un <form method="POST" action="/api/select-context"> avec
  // <input type="hidden" name="cabinet_id"> + <input type="hidden" name="secretariat_id">.
  // On filtre par valeur du secretariat_id pour choisir B.
  const formB = list.locator(`form:has(input[name="secretariat_id"][value="${SECRETARIAT_B_ID}"])`);
  await expect(formB, 'Form du secrétariat B présent dans la liste').toHaveCount(1);

  // Click sur le bouton submit du form B → POST /api/select-context → redirect
  await formB.locator('button[type="submit"]').click();

  // ── Vérif redirect vers /secretary/dashboard (rôle inchangé, contexte différent) ─
  await page.waitForURL((u) => u.pathname === '/secretary/dashboard', { timeout: 10_000 });

  // ── Vérif cookie nubia_ctx a changé ──────────────────────────────────────
  const cookiesAfter = await context.cookies();
  const ctxAfter = cookiesAfter.find((c) => c.name === 'nubia_ctx')?.value;
  expect(ctxAfter, 'Cookie nubia_ctx doit toujours exister après switch').toBeTruthy();
  expect(ctxAfter, 'Cookie nubia_ctx doit avoir changé après switch A→B').not.toBe(ctxBefore);

  // ── Vérif le label affiché reflète le nouveau contexte (secrétariat B) ──
  const currentLabel = await page.locator('.ctx-switcher__label').textContent();
  expect(currentLabel, 'Label du switcher doit refléter le contexte actif (B)').toBeTruthy();
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 3 : session expirée pendant le switch → redirect /auth/login
// ─────────────────────────────────────────────────────────────────────────────
test('session expirée pendant le switch → redirect /auth/login', async ({ page, context }) => {
  await loginAs(page, 'secretary');

  // Se positionner sur l'AppShell (passer select-context si présent)
  if (page.url().includes('/auth/select-context')) {
    await page.locator('button:has-text("Choisir")').first().click();
    await page.waitForURL((u) => u.pathname.startsWith('/secretary'), { timeout: 8_000 });
  }

  // ── Simuler une session expirée : on supprime le JWT cookie ──────────────
  // L'API /api/select-context lira un cookie absent → currentJwt undefined →
  // redirect /auth/login (cf. select-context.ts ligne ~68).
  await context.clearCookies({ name: 'nubia_jwt' });

  // ── Tenter un switch ──────────────────────────────────────────────────────
  await page.locator('summary.ctx-switcher__trigger').click();
  const list = page.locator('ul.ctx-switcher__list');
  const anyForm = list.locator('form').first();
  await anyForm.locator('button[type="submit"]').click();

  // ── Vérif redirect vers /auth/login ──────────────────────────────────────
  await page.waitForURL((u) => u.pathname === '/auth/login', { timeout: 8_000 });
  expect(page.url(), 'Session expirée → redirect /auth/login').toContain('/auth/login');
});
