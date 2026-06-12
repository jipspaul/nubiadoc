/**
 * ES6 — Flow E2E : manager provisionne secrétaire (section C du PLAN-ATOMIC)
 *
 * Valide :
 *   1. Manager login → navigue vers /manager/personnel
 *   2. Charge le secrétariat A → ajoute une secrétaire (POST /v1/cabinet/secretariats/:id/staff)
 *   3. Logout, login en tant que la nouvelle secrétaire
 *   4. Vérif : page /secretary/dashboard accessible (secrétariat A scopé)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2+P10+P11+P13.
 *   R13 (POST /v1/cabinet/secretariats/:id/staff) opérationnel.
 *   W58 (/manager/personnel) opérationnel.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL         URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL     URL de l'API backend (défaut http://localhost:38030)
 *   SEED_MANAGER_EMAIL     Email manager seed (défaut manager.demo@nubia.test)
 *   SEED_MANAGER_PASSWORD  Mot de passe manager seed (défaut NubiaDemo1!)
 *   SEED_SECRETARIAT_A_ID  UUID secrétariat A (défaut 00000000-0000-0000-0000-000000000201)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const SECRETARIAT_A_ID =
  process.env.SEED_SECRETARIAT_A_ID ?? '00000000-0000-0000-0000-000000000201';

// E-mail unique par run pour éviter les conflits si le stack n'est pas réinitialisé
const NEW_SECRETARY_EMAIL = `es6-sec-${Date.now()}@nubia.test`;
const NEW_SECRETARY_PASSWORD = 'NubiaDemo1!';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario principal : manager provisionne → secrétaire se connecte → dashboard
// ─────────────────────────────────────────────────────────────────────────────
test('manager provisionne secrétaire → la secrétaire se connecte → dashboard accessible', async ({ page }) => {
  // ── 1. Login manager ──────────────────────────────────────────────────────
  await loginAs(page, 'manager');

  // Après login, le manager est redirigé hors de /auth/login.
  // On navigue directement sur la page de gestion du personnel.
  await page.goto('/manager/personnel');
  await expect(page.locator('h1'), 'Page /manager/personnel : h1 visible').toBeVisible({ timeout: 10_000 });

  // ── 2. Charger le secrétariat A ───────────────────────────────────────────
  await page.locator('input[name="secretariat_id"]').fill(SECRETARIAT_A_ID);
  await page.locator('#form-select-secretariat button[type="submit"]').click();

  // Attendre que la section "Ajouter un secrétaire" soit affichée
  await expect(
    page.locator('#section-add'),
    'Section "Ajouter un secrétaire" doit apparaître après chargement du secrétariat',
  ).toBeVisible({ timeout: 8_000 });

  // ── 3. Ajouter la nouvelle secrétaire ─────────────────────────────────────
  await page.locator('#staff-email').fill(NEW_SECRETARY_EMAIL);
  await page.locator('#form-add-staff button[type="submit"]').click();

  // Vérifier le message de succès (ou 409 si déjà présent — acceptable)
  const addStatusEl = page.locator('#add-status');
  await expect(addStatusEl, 'Statut ajout doit être visible').toBeVisible({ timeout: 8_000 });

  const statusText = await addStatusEl.textContent();
  const isSuccess = statusText?.includes('succès') ?? false;
  const isConflict = statusText?.includes('409') || statusText?.includes('déjà membre') || false;
  expect(
    isSuccess || isConflict,
    `Statut inattendu après ajout secrétaire : "${statusText}"`,
  ).toBe(true);

  // ── 4. Logout manager ─────────────────────────────────────────────────────
  await clearSession(page);

  // ── 5. Login en tant que la nouvelle secrétaire ───────────────────────────
  // La secrétaire fraîchement provisionnée n'a qu'un seul secrétariat (A) :
  // le login doit la rediriger directement vers /secretary/dashboard
  // sans passer par /auth/select-context.
  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill(NEW_SECRETARY_EMAIL);
  await page.locator('input[name="password"]').fill(NEW_SECRETARY_PASSWORD);
  await page.locator('form#login-form button[type="submit"]').click();

  // Attendre la redirection (soit /secretary/dashboard, soit /auth/select-context)
  await page.waitForURL(
    (u) => u.pathname.startsWith('/secretary') || u.pathname === '/auth/select-context',
    { timeout: 12_000 },
  );

  // Si sélection de contexte requise, choisir le secrétariat A
  if (page.url().includes('/auth/select-context')) {
    await page.locator('button:has-text("Choisir")').first().click();
    await page.waitForURL((u) => u.pathname.startsWith('/secretary'), { timeout: 8_000 });
  }

  // ── 6. Vérif : dashboard secrétaire accessible ───────────────────────────
  await page.goto('/secretary/dashboard');
  await expect(
    page.locator('h1'),
    'Dashboard secrétaire (/secretary/dashboard) doit afficher un h1',
  ).toBeVisible({ timeout: 10_000 });
});
