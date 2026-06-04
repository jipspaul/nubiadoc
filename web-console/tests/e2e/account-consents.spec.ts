import { test, expect } from '@playwright/test';

test('le formulaire /account/consents est visible avec le champ et le bouton', async ({ page }) => {
  await page.goto('/test/account/consents');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/account/consents');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/account/consents');
});
