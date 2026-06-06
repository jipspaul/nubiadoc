import { test, expect } from '@playwright/test';

test('render — /cabinet/settings affiche les deux formulaires GET et PATCH', async ({ page }) => {
  await page.goto('/cabinet/settings');
  await expect(page.locator('input[name="access_token"]').first()).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /patch/i })).toBeVisible();
  await expect(page.locator('#get-result')).toBeVisible();
  await expect(page.locator('#patch-result')).toBeVisible();
});

test('happy path — GET 200 affiche les réglages du cabinet', async ({ page }) => {
  await page.route('**/v1/cabinet', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: '00000000-0000-0000-0000-000000000001',
        raison_sociale: 'Cabinet Dupont',
        address: '12 rue de la Paix, 75001 Paris',
        phone: '+33 1 23 45 67 89',
      }),
    });
  });

  await page.goto('/cabinet/settings');
  await page.locator('#settings-get-form input[name="access_token"]').fill('pro-admin-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#get-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#get-result')).toContainText('Cabinet Dupont');
});

test('error path — PATCH 403 avec token non-admin affiché dans le résultat', async ({ page }) => {
  await page.route('**/v1/cabinet', (route) => {
    if (route.request().method() !== 'PATCH') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/cabinet/settings');
  await page.locator('#settings-patch-form input[name="access_token"]').fill('non-admin-token');
  await page.locator('#settings-patch-form input[name="raison_sociale"]').fill('Cabinet Test');
  await page.getByRole('button', { name: /patch/i }).click();
  await expect(page.locator('#patch-result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#patch-result')).toContainText('forbidden');
});
