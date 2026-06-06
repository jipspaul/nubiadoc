import { test, expect } from '@playwright/test';

test('le formulaire /test/billing/quotes est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/billing/quotes');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="status"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /^GET$/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('200 => GET valide retourne la liste des devis avec montants', async ({ page }) => {
  await page.route('**/v1/quotes', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: '00000000-0000-0000-0000-000000000001', status: 'pending', total_cents: 15000 },
        { id: '00000000-0000-0000-0000-000000000002', status: 'signed', total_cents: 32000 },
      ]),
    });
  });

  await page.goto('/test/billing/quotes');
  await page.locator('input[name="access_token"]').fill('valid-patient-token');
  await page.getByRole('button', { name: /^GET$/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('total_cents');
  await expect(page.locator('#result')).toContainText('15000');
});

test('403 => accès pro refusé affiché', async ({ page }) => {
  await page.route('**/v1/quotes', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/test/billing/quotes');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.getByRole('button', { name: /^GET$/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('forbidden');
});

test('401 => token invalide, accès non autorisé affiché', async ({ page }) => {
  await page.route('**/v1/quotes', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/test/billing/quotes');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.getByRole('button', { name: /^GET$/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});
