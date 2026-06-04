import { test, expect } from '@playwright/test';

test('le formulaire /auth/password-reset est visible avec les champs et le bouton', async ({ page }) => {
  await page.goto('/test/auth/password-reset');
  await expect(page.locator('input[name="token"]')).toBeVisible();
  await expect(page.locator('input[name="new_password"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /réinitialiser/i })).toBeVisible();
});

test('submit avec token bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/auth/password-reset');
  await page.locator('input[name="token"]').fill('fake-reset-token');
  await page.locator('input[name="new_password"]').fill('Password1');
  await page.getByRole('button', { name: /réinitialiser/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/auth/password-reset');
});
