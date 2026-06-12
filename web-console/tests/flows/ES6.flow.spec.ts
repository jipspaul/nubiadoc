/**
 * ES6 — Flow E2E : manager provisionne secrétaire (section C du PLAN-ATOMIC)
 *
 * Valide :
 *   1. Manager (admin) login → navigue vers /manager/personnel
 *   2. Charge le secrétariat A → ajoute une secrétaire (POST /v1/cabinet/secretariats/:id/staff)
 *      Contrat réel R13 : 201 {user_id, activation_token} — le compte est créé
 *      sans mot de passe ; l'activation passe par POST /v1/auth/password/reset.
 *   3. Activation du compte (reset token → mot de passe), logout manager,
 *      login en tant que la nouvelle secrétaire
 *   4. Vérif : page /secretary/dashboard accessible (secrétariat A scopé)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed réel.
 *   R13 (POST /v1/cabinet/secretariats/:id/staff) opérationnel.
 *   W58 (/manager/personnel) opérationnel.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL         URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL     URL de l'API backend (défaut http://localhost:38030)
 *   SEED_MANAGER_EMAIL     Email admin/manager seed (défaut admin@cabinet-lyon.test via env)
 *   SEED_MANAGER_PASSWORD  Mot de passe manager seed
 *   SEED_SECRETARIAT_A_ID  UUID secrétariat A (défaut 19870000-0000-0000-0000-000000000001)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE = process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SECRETARIAT_A_ID =
  process.env.SEED_SECRETARIAT_A_ID ?? '19870000-0000-0000-0000-000000000001';

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
  // Capture la réponse du POST /staff pour récupérer l'activation_token
  // (contrat R13 : le compte est créé sans mot de passe).
  await page.locator('#staff-email').fill(NEW_SECRETARY_EMAIL);

  const [staffResponse] = await Promise.all([
    page.waitForResponse(
      (resp) =>
        resp.url().includes(`/v1/cabinet/secretariats/${SECRETARIAT_A_ID}/staff`) &&
        resp.request().method() === 'POST',
      { timeout: 8_000 },
    ),
    page.locator('#form-add-staff button[type="submit"]').click(),
  ]);

  expect(
    [200, 201],
    `POST /v1/cabinet/secretariats/:id/staff attendu 200/201, reçu ${staffResponse.status()}`,
  ).toContain(staffResponse.status());

  const staffBody = (await staffResponse.json()) as {
    user_id?: string;
    activation_token?: string | null;
  };
  expect(staffBody.user_id, 'user_id doit être présent dans la réponse staff').toBeTruthy();
  // Email unique par run → toujours un nouveau compte → token d'activation présent.
  const activationToken = staffBody.activation_token ?? '';
  expect(activationToken, 'activation_token attendu pour un nouveau compte').toBeTruthy();

  // Vérifier le message de succès affiché par la page
  const addStatusEl = page.locator('#add-status');
  await expect(addStatusEl, 'Statut ajout doit être visible').toBeVisible({ timeout: 8_000 });
  await expect(addStatusEl).toContainText('succès', { timeout: 8_000 });

  // ── 3bis. Activer le compte : POST /v1/auth/password/reset → 204 ──────────
  const resetStatus = await page.evaluate(
    async ({
      apiBase,
      token,
      password,
    }: {
      apiBase: string;
      token: string;
      password: string;
    }) => {
      const resp = await fetch(`${apiBase}/v1/auth/password/reset`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, new_password: password }),
      });
      return resp.status;
    },
    { apiBase: API_BASE, token: activationToken, password: NEW_SECRETARY_PASSWORD },
  );

  expect(
    resetStatus,
    `POST /v1/auth/password/reset attendu 204, reçu ${resetStatus}`,
  ).toBe(204);

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
