import { test, expect } from '@playwright/test';

test('le formulaire /test/scheduling/appointments-cancel est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/scheduling/appointments-cancel');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /annuler ce rdv/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => POST cancel retourne 200 { status: "cancelled" }', async ({ page }) => {
  await page.route('**/v1/appointments/*/cancel', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ status: 'cancelled' }),
    });
  });

  await page.goto('/test/scheduling/appointments-cancel');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /annuler ce rdv/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('cancelled');
});

test('erreur => annuler un RDV déjà cancelled retourne 409 invalid_status', async ({ page }) => {
  await page.route('**/v1/appointments/*/cancel', (route) => {
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'invalid_status' }),
    });
  });

  await page.goto('/test/scheduling/appointments-cancel');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.getByRole('button', { name: /annuler ce rdv/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('invalid_status');
});
