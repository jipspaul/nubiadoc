import { test, expect } from '@playwright/test';

test('render — /patient/profil/proches affiche le titre et le loading', async ({ page }) => {
  // Block the API so the loading state stays visible long enough to assert.
  await page.route('**/v1/account/dependents', (route) => new Promise(() => {}));
  await page.goto('/patient/profil/proches');
  await expect(page.getByRole('heading', { name: /mes proches/i })).toBeVisible();
  await expect(page.locator('#proches-loading')).toBeVisible();
});

test('happy path — liste vide : message "aucun proche" affiché', async ({ page }) => {
  await page.route('**/v1/account/dependents', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([]),
    }),
  );
  await page.goto('/patient/profil/proches');
  await expect(page.locator('#proches-empty')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#proches-list')).toBeHidden();
});

test('happy path — liste remplie : proches affichés', async ({ page }) => {
  await page.route('**/v1/account/dependents', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: '1', first_name: 'Léa', last_name: 'Dupont', relationship: 'enfant', date_of_birth: '2015-03-10' },
      ]),
    }),
  );
  await page.goto('/patient/profil/proches');
  await expect(page.locator('#proches-list')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('.proche-name')).toContainText('Léa Dupont');
});

test('error path — API 401 : message d\'erreur affiché', async ({ page }) => {
  await page.route('**/v1/account/dependents', (route) =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ status: 401, code: 'unauthenticated' }),
    }),
  );
  await page.goto('/patient/profil/proches');
  await expect(page.locator('#proches-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#proches-list')).toBeHidden();
});
