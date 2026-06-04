import { test, expect } from '@playwright/test';

test('le formulaire /account/coverage-card est visible avec les champs requis', async ({ page }) => {
  await page.goto('/account/coverage-card');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="side"][value="recto"]')).toBeVisible();
  await expect(page.locator('input[name="side"][value="verso"]')).toBeVisible();
  await expect(page.locator('input[name="file"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /upload/i })).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/account/coverage-card');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="side"][value="recto"]').check();
  await page.locator('input[name="file"]').setInputFiles({
    name: 'test.png',
    mimeType: 'image/png',
    buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64'),
  });
  await page.getByRole('button', { name: /upload/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/account/coverage-card');
});
