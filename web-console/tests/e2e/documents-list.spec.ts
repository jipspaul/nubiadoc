import { test, expect } from '@playwright/test';

test('le formulaire /test/documents/list est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/documents/list');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('select[name="category"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /refresh/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('submit avec token bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/documents/list');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('select[name="category"]').selectOption('ordonnance');
  await page.getByRole('button', { name: /refresh/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/documents/list');
});
