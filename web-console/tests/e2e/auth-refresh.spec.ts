import { test, expect } from '@playwright/test';

test('le formulaire /auth/refresh est visible avec le champ et le bouton', async ({ page }) => {
  await page.goto('/test/auth/refresh');
  await expect(page.locator('input[name="refresh_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('submit avec token bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/auth/refresh');
  await page.locator('input[name="refresh_token"]').fill('fake-refresh-token');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/auth/refresh');
});
