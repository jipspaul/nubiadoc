import { test, expect } from '@playwright/test';

test('le formulaire /test/scheduling/queue est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/scheduling/queue');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('soumission renvoie HTTP ou erreur réseau (pas de backend en CI)', async ({ page }) => {
  await page.goto('/test/scheduling/queue');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/scheduling/queue');
});
