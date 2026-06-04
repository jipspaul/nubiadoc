import { test, expect } from '@playwright/test';

test('le formulaire /account/consents-update est visible avec les champs et le bouton', async ({ page }) => {
  await page.goto('/test/account/consents-update');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="purpose"]')).toBeVisible();
  await expect(page.locator('input[name="granted"][value="true"]')).toBeVisible();
  await expect(page.locator('input[name="granted"][value="false"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/account/consents-update');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="purpose"]').fill('soins');
  await page.locator('input[name="granted"][value="true"]').check();
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/account/consents-update');
});
