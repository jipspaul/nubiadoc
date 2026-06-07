import { test, expect } from '@playwright/test';

test('render — /patient/profil affiche le titre et le loading', async ({ page }) => {
  // Block the API so the loading state stays visible long enough to assert.
  await page.route('**/v1/account', (route) => new Promise(() => {}));
  await page.goto('/patient/profil');
  await expect(page.getByRole('heading', { name: /mon profil/i })).toBeVisible();
  await expect(page.locator('#profil-loading')).toBeVisible();
});

test('happy path — profil chargé : formulaire visible avec les données', async ({ page }) => {
  await page.route('**/v1/account', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        first_name: 'Marie',
        last_name: 'Dupont',
        email: 'marie.dupont@example.com',
        phone: '+33612345678',
        date_of_birth: '1990-05-15',
      }),
    }),
  );
  await page.goto('/patient/profil');
  await expect(page.locator('#profil-form')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('input[name="first_name"]')).toHaveValue('Marie');
  await expect(page.locator('input[name="last_name"]')).toHaveValue('Dupont');
  await expect(page.locator('input[name="email"]')).toHaveValue('marie.dupont@example.com');
});

test('error path — API 401 : message d\'erreur affiché, formulaire caché', async ({ page }) => {
  await page.route('**/v1/account', (route) =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ status: 401, code: 'unauthenticated' }),
    }),
  );
  await page.goto('/patient/profil');
  await expect(page.locator('#profil-loading')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#profil-loading')).toContainText(/impossible/i);
  await expect(page.locator('#profil-form')).toBeHidden();
});
