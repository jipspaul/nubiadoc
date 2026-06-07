import { test, expect } from '@playwright/test';

test('render — /patient/profil/consentements affiche le titre et le loading', async ({ page }) => {
  // Block the API so the loading state stays visible long enough to assert.
  await page.route('**/v1/account/consents', (route) => new Promise(() => {}));
  await page.goto('/patient/profil/consentements');
  await expect(page.getByRole('heading', { name: /gestion des consentements/i })).toBeVisible();
  await expect(page.locator('#consents-loading')).toBeVisible();
});

test('error path — API 401 : message d\'erreur affiché, liste cachée', async ({ page }) => {
  await page.route('**/v1/account/consents', (route) =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ status: 401, code: 'unauthenticated' }),
    }),
  );
  await page.goto('/patient/profil/consentements');
  await expect(page.locator('#consents-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#consents-list')).toBeHidden();
});
