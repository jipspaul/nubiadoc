import { test, expect } from '@playwright/test';

test('le formulaire /appointments/preparation est visible avec les champs requis', async ({ page }) => {
  await page.goto('/appointments/preparation');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /charger préparation/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => GET préparation retourne 200, Carte Vitale visible dans la liste', async ({ page }) => {
  await page.route('**/v1/appointments/*/preparation', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        provider: { name: 'Dr. Dupont' },
        establishment: { address: '12 rue de la Paix, 75001 Paris' },
        bring: [
          { label: 'Carte Vitale', required: true },
          { label: 'Carte mutuelle', required: false },
        ],
        reminder_at: '2025-06-01T08:00:00Z',
      }),
    });
  });

  await page.goto('/appointments/preparation');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /charger préparation/i }).click();
  await expect(page.locator('#bring-list')).toContainText('Carte Vitale', { timeout: 5000 });
  await expect(page.locator('#provider-name')).toContainText('Dr. Dupont');
  await expect(page.locator('#establishment-address')).toContainText('12 rue de la Paix');
});

test('erreur => UUID inexistant retourne 404, message d\'erreur affiché', async ({ page }) => {
  await page.route('**/v1/appointments/*/preparation', (route) => {
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'appointment_not_found' }),
    });
  });

  await page.goto('/appointments/preparation');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000099');
  await page.getByRole('button', { name: /charger préparation/i }).click();
  await expect(page.locator('#error-message')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#error-message')).toContainText('404');
});
