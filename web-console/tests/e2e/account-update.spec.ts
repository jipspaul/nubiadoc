import { test, expect } from '@playwright/test';

test('le formulaire /account/update est visible avec les champs requis', async ({ page }) => {
  await page.goto('/account/update');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="first_name"]')).toBeVisible();
  await expect(page.locator('input[name="last_name"]')).toBeVisible();
  await expect(page.locator('input[name="birth_date"]')).toBeVisible();
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="phone"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/account/update');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="first_name"]').fill('Marie');
  await page.locator('input[name="last_name"]').fill('Dupont');
  await page.locator('input[name="email"]').fill('marie.dupont@example.com');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/account/update');
});
