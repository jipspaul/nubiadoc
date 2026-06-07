import { test, expect } from '@playwright/test';

test('render — /patient/profil/couverture affiche le titre et le loading', async ({ page }) => {
  // Block the API so the loading state stays visible long enough to assert.
  await page.route('**/v1/account/coverage', (route) => new Promise(() => {}));
  await page.goto('/patient/profil/couverture');
  await expect(page.getByRole('heading', { name: /couverture santé/i })).toBeVisible();
  await expect(page.locator('#couverture-loading')).toBeVisible();
});

test('happy path — formulaire pré-rempli avec les données de couverture', async ({ page }) => {
  await page.route('**/v1/account/coverage', (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          regime: 'Sécurité sociale générale',
          mutual: 'MGEN',
          mutual_number: '123456789',
        }),
      });
    } else {
      route.continue();
    }
  });
  await page.goto('/patient/profil/couverture');
  await expect(page.locator('#couverture-form')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('input[name="regime"]')).toHaveValue('Sécurité sociale générale');
  await expect(page.locator('input[name="mutual"]')).toHaveValue('MGEN');
});

test('error path — API 401 : message d\'erreur affiché', async ({ page }) => {
  await page.route('**/v1/account/coverage', (route) =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ status: 401, code: 'unauthenticated' }),
    }),
  );
  await page.goto('/patient/profil/couverture');
  await expect(page.locator('#couverture-loading')).toContainText(/impossible/i, { timeout: 5000 });
  await expect(page.locator('#couverture-form')).toBeHidden();
});
