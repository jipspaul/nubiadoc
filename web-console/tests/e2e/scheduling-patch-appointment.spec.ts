import { test, expect } from '@playwright/test';

test('le formulaire /scheduling/patch-appointment est visible avec les champs requis', async ({ page }) => {
  await page.goto('/scheduling/patch-appointment');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.locator('input[name="starts_at"]')).toBeVisible();
  await expect(page.locator('input[name="motif"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /modifier ce rdv/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => PATCH retourne 200 avec appointment_id et status', async ({ page }) => {
  await page.route('**/v1/appointments/*', (route) => {
    if (route.request().method() === 'PATCH') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ appointment_id: '00000000-0000-0000-0000-000000000001', status: 'confirmed' }),
      });
    } else {
      route.continue();
    }
  });

  await page.goto('/scheduling/patch-appointment');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('input[name="motif"]').fill('détartrage');
  await page.getByRole('button', { name: /modifier ce rdv/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('appointment_id');
});

test('erreur => PATCH trop tard retourne 409 too_late visible dans l\'UI', async ({ page }) => {
  await page.route('**/v1/appointments/*', (route) => {
    if (route.request().method() === 'PATCH') {
      route.fulfill({
        status: 409,
        contentType: 'application/json',
        body: JSON.stringify({ code: 'too_late' }),
      });
    } else {
      route.continue();
    }
  });

  await page.goto('/scheduling/patch-appointment');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('input[name="motif"]').fill('nettoyage');
  await page.getByRole('button', { name: /modifier ce rdv/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('too_late');
});
