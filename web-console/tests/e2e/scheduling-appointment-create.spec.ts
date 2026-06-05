import { test, expect } from '@playwright/test';

test('le formulaire /scheduling/appointment-create est visible avec les champs requis', async ({ page }) => {
  await page.goto('/scheduling/appointment-create');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="provider_id"]')).toBeVisible();
  await expect(page.locator('input[name="starts_at"]')).toBeVisible();
  await expect(page.locator('input[name="motif"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /prendre rdv/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => POST valide retourne 201 { appointment_id }', async ({ page }) => {
  await page.route('**/v1/appointments', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ appointment_id: '00000000-0000-0000-0000-000000000001', status: 'confirmed' }),
    });
  });

  await page.goto('/scheduling/appointment-create');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="provider_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('input[name="starts_at"]').fill('2026-07-01T10:00');
  await page.locator('input[name="motif"]').fill('consultation');
  await page.getByRole('button', { name: /prendre rdv/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('appointment_id');
});

test('double-booking => POST retourne 409 { code: "slot_taken" }', async ({ page }) => {
  await page.route('**/v1/appointments', (route) => {
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'slot_taken' }),
    });
  });

  await page.goto('/scheduling/appointment-create');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="provider_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('input[name="starts_at"]').fill('2026-07-01T10:00');
  await page.locator('input[name="motif"]').fill('consultation');
  await page.getByRole('button', { name: /prendre rdv/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('slot_taken');
});
