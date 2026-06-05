import { test, expect } from '@playwright/test';

test('le formulaire /appointments/checkin est visible avec les champs requis', async ({ page }) => {
  await page.goto('/appointments/checkin');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.locator('select[name="method"]')).toBeVisible();
  await expect(page.locator('input[name="lat"]')).toBeVisible();
  await expect(page.locator('input[name="lon"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /check-in/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => POST checkin method=manual retourne 200 checked_in', async ({ page }) => {
  await page.route('**/v1/appointments/*/checkin', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ status: 'checked_in' }),
    });
  });

  await page.goto('/appointments/checkin');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('select[name="method"]').selectOption('manual');
  await page.getByRole('button', { name: /check-in/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('checked_in');
});

test('erreur => RDV non confirmé retourne 409 invalid_status visible dans l\'UI', async ({ page }) => {
  await page.route('**/v1/appointments/*/checkin', (route) => {
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'invalid_status' }),
    });
  });

  await page.goto('/appointments/checkin');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('select[name="method"]').selectOption('manual');
  await page.getByRole('button', { name: /check-in/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('invalid_status');
});
