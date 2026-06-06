import { test, expect } from '@playwright/test';

test('le formulaire /test/scheduling/call-next est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/scheduling/call-next');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /appeler le suivant/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('200 avec patient => patient info affiché dans le résultat', async ({ page }) => {
  await page.route('**/v1/cabinet/waiting-room/call-next', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ patient: { id: 'patient-uuid-1', display_name: 'Alice Martin' } }),
    });
  });

  await page.goto('/test/scheduling/call-next');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.getByRole('button', { name: /appeler le suivant/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('Alice Martin');
});

test('200 sans patient => file vide, résultat affiché', async ({ page }) => {
  await page.route('**/v1/cabinet/waiting-room/call-next', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ patient: null }),
    });
  });

  await page.goto('/test/scheduling/call-next');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.getByRole('button', { name: /appeler le suivant/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('null');
});

test('403 => message d\'erreur visible dans l\'UI', async ({ page }) => {
  await page.route('**/v1/cabinet/waiting-room/call-next', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/test/scheduling/call-next');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.getByRole('button', { name: /appeler le suivant/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('forbidden');
});
