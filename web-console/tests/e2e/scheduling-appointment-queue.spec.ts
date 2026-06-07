import { test, expect } from '@playwright/test';

test('le formulaire /scheduling/appointment-queue est visible avec les champs requis', async ({ page }) => {
  await page.goto('/scheduling/appointment-queue');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => GET queue retourne 200 avec position, est_wait_min, status', async ({ page }) => {
  await page.route('**/v1/appointments/*/queue', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ position: 3, est_wait_min: 12, status: 'waiting' }),
    });
  });

  await page.goto('/scheduling/appointment-queue');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#q-position')).toContainText('3');
  await expect(page.locator('#q-wait')).toContainText('12 min');
  await expect(page.locator('#q-status')).toContainText('waiting');
});

test('RDV introuvable => 404 visible dans l\'UI', async ({ page }) => {
  await page.route('**/v1/appointments/*/queue', (route) => {
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found' }),
    });
  });

  await page.goto('/scheduling/appointment-queue');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000099');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 404', { timeout: 5000 });
});
