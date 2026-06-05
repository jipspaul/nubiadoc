import { test, expect } from '@playwright/test';

test('le formulaire /scheduling/checkin-appointment est visible avec les champs requis', async ({ page }) => {
  await page.goto('/scheduling/checkin-appointment');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /check-in/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => POST checkin retourne 200 { status: "checked_in" }', async ({ page }) => {
  await page.route('**/v1/appointments/*/checkin', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ status: 'checked_in' }),
    });
  });

  await page.goto('/scheduling/checkin-appointment');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /check-in/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('checked_in');
});

test('double check-in => 409 visible dans l\'UI', async ({ page }) => {
  await page.route('**/v1/appointments/*/checkin', (route) => {
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'already_checked_in' }),
    });
  });

  await page.goto('/scheduling/checkin-appointment');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.getByRole('button', { name: /check-in/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('already_checked_in');
});
