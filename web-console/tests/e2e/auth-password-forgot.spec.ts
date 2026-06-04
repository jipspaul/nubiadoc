import { test, expect } from '@playwright/test';

test('le formulaire /auth/password-forgot est visible avec le champ et le bouton', async ({ page }) => {
  await page.goto('/test/auth/password-forgot');
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('submit avec email bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/auth/password-forgot');
  await page.locator('input[name="email"]').fill('test@example.com');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/auth/password-forgot');
});
