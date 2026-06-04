import { test, expect } from '@playwright/test';

test('la page /register se rend avec le formulaire et le lien retour login', async ({ page }) => {
  await page.goto('/register');
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="password"]')).toBeVisible();
  await expect(page.locator('input[name="confirm_password"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /créer le compte/i })).toBeVisible();
  await expect(page.getByRole('link', { name: /se connecter/i })).toBeVisible();
});

test('submit avec un email aléatoire affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/register');
  await page.locator('input[name="email"]').fill('test-random@example.com');
  await page.locator('input[name="password"]').fill('TestPassword123!');
  await page.locator('input[name="confirm_password"]').fill('TestPassword123!');
  await page.getByRole('button', { name: /créer le compte/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
});
