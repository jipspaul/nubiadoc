import { test, expect } from '@playwright/test';

test('le formulaire /auth/register est visible avec les champs et le bouton', async ({ page }) => {
  await page.goto('/auth/register');
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="password"]')).toBeVisible();
  await expect(page.locator('input[name="cgu_version"]')).toBeVisible();
  await expect(page.locator('input[name="accept_cgu"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/auth/register');
  await page.locator('input[name="email"]').fill('fake@example.com');
  await page.locator('input[name="password"]').fill('FakePassword123!');
  await page.locator('input[name="cgu_version"]').fill('1.0');
  await page.locator('input[name="accept_cgu"]').check();
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/auth/register');
});
