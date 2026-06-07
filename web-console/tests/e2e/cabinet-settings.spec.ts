import { test, expect } from '@playwright/test';

test('render — /cabinet/settings affiche les deux formulaires GET et PATCH', async ({ page }) => {
  await page.goto('/cabinet/settings');
  await expect(page.locator('input[name="access_token"]').first()).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /patch/i })).toBeVisible();
  await expect(page.locator('#get-result')).toBeVisible();
  await expect(page.locator('#patch-result')).toBeVisible();
});

test('happy path — GET 200 affiche raison_sociale, siret et settings', async ({ page }) => {
  await page.route('**/v1/cabinet', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: '00000000-0000-0000-0000-000000000001',
        raison_sociale: 'Cabinet Dupont',
        siret: '12345678900012',
        address: '12 rue de la Paix, 75001 Paris',
        phone: '+33 1 23 45 67 89',
        settings: {
          horaires: { lundi: '09:00-18:00' },
          branding: { couleur_principale: '#1a73e8' },
        },
      }),
    });
  });

  await page.goto('/cabinet/settings');
  await page.locator('#settings-get-form input[name="access_token"]').fill('pro-admin-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#get-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#get-result')).toContainText('Cabinet Dupont');
  await expect(page.locator('#get-result')).toContainText('12345678900012');
  await expect(page.locator('#get-result')).toContainText('settings');
});

test('error path — GET 401 sans token affiche unauthenticated', async ({ page }) => {
  await page.route('**/v1/cabinet', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthenticated' }),
    });
  });

  await page.goto('/cabinet/settings');
  await page.locator('#settings-get-form input[name="access_token"]').fill('');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#get-result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#get-result')).toContainText('unauthenticated');
});
