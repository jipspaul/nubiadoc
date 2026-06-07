import { test, expect } from '@playwright/test';

test('le formulaire /test/scheduling/callback-request est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/scheduling/callback-request');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /demander un rappel/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => POST callback-request retourne 202', async ({ page }) => {
  await page.route('**/v1/appointments/*/callback-request', (route) => {
    route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ status: 'queued' }) });
  });

  await page.goto('/test/scheduling/callback-request');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /demander un rappel/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 202', { timeout: 5000 });
});

test('erreur => 404 not_found visible dans l\'UI', async ({ page }) => {
  await page.route('**/v1/appointments/*/callback-request', (route) => {
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found' }),
    });
  });

  await page.goto('/test/scheduling/callback-request');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000099');
  await page.getByRole('button', { name: /demander un rappel/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 404', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('not_found');
});
