import { test, expect } from '@playwright/test';

test('le formulaire /scheduling/cancel-appointment est visible avec les champs requis', async ({ page }) => {
  await page.goto('/scheduling/cancel-appointment');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /annuler ce rdv/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => POST cancel retourne 204 (aucun contenu)', async ({ page }) => {
  await page.route('**/v1/appointments/*/cancel', (route) => {
    route.fulfill({ status: 204, body: '' });
  });

  await page.goto('/scheduling/cancel-appointment');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /annuler ce rdv/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 204', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('aucun contenu');
});

test('erreur => annuler hors délai retourne 409 too_late', async ({ page }) => {
  await page.route('**/v1/appointments/*/cancel', (route) => {
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'too_late' }),
    });
  });

  await page.goto('/scheduling/cancel-appointment');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.getByRole('button', { name: /annuler ce rdv/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('too_late');
});
