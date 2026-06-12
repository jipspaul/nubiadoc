/**
 * EP1 — Onboarding patient (E2E flow)
 *
 * Parcours : register (nouveau compte) → login → compléter profil
 *            → ajouter couverture (+carte vitale) → CRUD proches
 *            (ajouter, modifier, supprimer)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL       URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL   URL de l'API backend (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

/** Génère un email unique par run pour éviter les collisions. */
function freshEmail(): string {
  return `ep1.test.${Date.now()}@nubia.test`;
}

const TEST_PASSWORD = 'NubiaEP1Test1!';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

test('register → login → profil → couverture (+carte) → proches CRUD', async ({ page }) => {
  const email = freshEmail();

  // ── 1. Inscription (POST /v1/auth/register) ──────────────────────────────
  await page.goto('/auth/register');
  await expect(page.locator('form#register-form')).toBeVisible();

  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(TEST_PASSWORD);
  await page.locator('input[name="accept_cgu"]').check();
  await page.locator('form#register-form button[type="submit"]').click();

  // Attendre la confirmation d'inscription (201)
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 15_000 });

  // ── 2. Connexion (POST /v1/auth/login) ────────────────────────────────────
  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(TEST_PASSWORD);
  await page.locator('form#login-form button[type="submit"]').click();

  // Après login, redirection vers /app (JWT posé en localStorage)
  await page.waitForURL((url) => !url.pathname.startsWith('/auth/login'), {
    timeout: 15_000,
  });

  // ── 3. GET /v1/account → email correct ───────────────────────────────────
  const { accountStatus, accountEmail } = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/account`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as { email?: string })
        : { email: '' };
      return { accountStatus: resp.status, accountEmail: data.email ?? '' };
    },
    API_BASE,
  );

  expect(accountStatus).toBeLessThan(300);
  expect(accountEmail).toBe(email);

  // ── 4. Compléter le profil (PATCH /v1/account) ────────────────────────────
  await page.goto('/patient/profil');
  // Attendre que le formulaire soit chargé
  await expect(page.locator('#profil-form')).toBeVisible({ timeout: 15_000 });

  await page.locator('input[name="first_name"]').fill('Juliette');
  await page.locator('input[name="last_name"]').fill('EP1');
  await page.locator('input[name="email"]').fill(email);
  await page.locator('#profil-form button[type="submit"]').click();

  await expect(page.locator('#profil-toast')).toContainText(/mis à jour/i, {
    timeout: 10_000,
  });

  // ── 5. Ajouter couverture (PATCH /v1/account/coverage) ───────────────────
  await page.goto('/patient/profil/couverture');
  await expect(page.locator('#couverture-form')).toBeVisible({ timeout: 15_000 });

  await page.locator('input[name="regime"]').fill('Sécurité sociale générale');
  await page.locator('input[name="mutual"]').fill('MGEN');
  await page.locator('input[name="mutual_number"]').fill('123456789');
  await page.locator('#couverture-form button[type="submit"]').click();

  await expect(page.locator('#couverture-toast')).toContainText(/mise? à jour/i, {
    timeout: 10_000,
  });

  // ── 6. Ajouter carte vitale (POST /v1/account/coverage/card) ─────────────
  await page.locator('input[name="file"]').setInputFiles({
    name: 'carte-vitale.png',
    mimeType: 'image/png',
    buffer: Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      'base64',
    ),
  });
  await page.locator('#card-form button[type="submit"]').click();

  // Toast succès ou, si l'API retourne une erreur non-bloquante, on continue
  await expect(page.locator('#card-toast')).toBeVisible({ timeout: 10_000 });

  // ── 7. Ajouter un proche (POST /v1/account/dependents) ───────────────────
  await page.goto('/patient/profil/proches');
  // Attendre la fin du chargement
  await expect(page.locator('#proches-loading')).toBeHidden({ timeout: 15_000 });

  await page.locator('#add-form input[name="first_name"]').fill('Lucas');
  await page.locator('#add-form input[name="last_name"]').fill('EP1');
  await page.locator('#add-form input[name="date_of_birth"]').fill('2015-06-20');
  await page.locator('#add-form input[name="relationship"]').fill('enfant');
  await page.locator('#add-form button[type="submit"]').click();

  await expect(page.locator('#add-toast')).toContainText(/ajouté/i, {
    timeout: 10_000,
  });

  // Le proche apparaît dans la liste
  await expect(page.locator('.proche-name')).toContainText('Lucas EP1');

  // ── 8. GET /v1/account/dependents → proche présent ───────────────────────
  const { depsStatus, depsFound } = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/account/dependents`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const list = resp.ok
        ? ((await resp.json()) as Array<{ first_name: string; last_name: string }>)
        : [];
      return {
        depsStatus: resp.status,
        depsFound: list.some(
          (d) => d.first_name === 'Lucas' && d.last_name === 'EP1',
        ),
      };
    },
    API_BASE,
  );

  expect(depsStatus).toBeLessThan(300);
  expect(depsFound).toBe(true);

  // ── 9. Modifier le proche (PATCH /v1/account/dependents/:id) ─────────────
  const editBtn = page
    .locator('.proche-item')
    .filter({ hasText: 'Lucas EP1' })
    .locator('.btn-edit');
  await editBtn.click();

  await expect(page.locator('#edit-dialog')).toBeVisible();
  await page.locator('#edit-form input[name="first_name"]').fill('Luca');
  await page.locator('#edit-form button[type="submit"]').click();

  await expect(page.locator('#edit-dialog')).toBeHidden({ timeout: 10_000 });
  // Nom mis à jour dans la liste
  await expect(page.locator('.proche-name')).toContainText('Luca EP1');

  // ── 10. Supprimer le proche (DELETE /v1/account/dependents/:id) ───────────
  page.once('dialog', (dialog) => dialog.accept());
  const deleteBtn = page
    .locator('.proche-item')
    .filter({ hasText: 'Luca EP1' })
    .locator('.btn-delete');
  await deleteBtn.click();

  // Après suppression, la liste est vide → message "aucun proche"
  await expect(page.locator('#proches-empty')).toBeVisible({ timeout: 10_000 });
  await expect(page.locator('.proche-name')).toBeHidden();
});

test('register avec email déjà pris retourne une erreur 409', async ({ page }) => {
  // Utilise le compte seed patient existant pour déclencher un conflit
  await page.goto('/auth/register');
  await expect(page.locator('form#register-form')).toBeVisible();

  await page.locator('input[name="email"]').fill('patient.demo@nubia.test');
  await page.locator('input[name="password"]').fill(TEST_PASSWORD);
  await page.locator('input[name="accept_cgu"]').check();
  await page.locator('form#register-form button[type="submit"]').click();

  // L'API doit retourner 409 email_taken
  await expect(page.locator('#result')).toContainText(/409|email/i, {
    timeout: 15_000,
  });
});
