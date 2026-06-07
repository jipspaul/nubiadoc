import { test, expect } from '@playwright/test';

test('le formulaire /test/scheduling/waiting-list est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/scheduling/waiting-list');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="provider_id"]')).toBeVisible();
  await expect(page.locator('input[name="available_from"]')).toBeVisible();
  await expect(page.locator('input[name="available_to"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /liste d'attente/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => POST valide retourne 201 { id, status }', async ({ page }) => {
  await page.route('**/v1/waiting-list', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ id: '00000000-0000-0000-0000-000000000001', status: 'pending' }),
    });
  });

  await page.goto('/test/scheduling/waiting-list');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="provider_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('input[name="available_from"]').fill('2026-07-01');
  await page.locator('input[name="available_to"]').fill('2026-07-31');
  await page.getByRole('button', { name: /liste d'attente/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('pending');
});
