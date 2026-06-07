import { test, expect } from '@playwright/test';

test('render — /praticien/profil-public affiche le titre et les sections', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/praticien/profil-public');
  await expect(page.getByRole('heading', { name: 'Profil public annuaire', level: 1 })).toBeVisible();
  await expect(page.locator('#form-provider')).toBeVisible();
  await expect(page.locator('#form-listing')).toBeVisible();
  await expect(page.locator('#form-verif-post')).toBeVisible();
});

test('error path — PATCH /v1/cabinet/provider répond 401 affiche HTTP 401', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/provider', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });
  await page.goto('/praticien/profil-public');
  await page.locator('input[name="specialty"]').fill('chirurgien-dentiste');
  await page.locator('#form-provider button[type="submit"]').click();
  await expect(page.locator('#result-provider')).toContainText('HTTP 401', { timeout: 5000 });
});
