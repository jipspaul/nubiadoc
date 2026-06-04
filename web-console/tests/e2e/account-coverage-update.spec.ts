import { test, expect } from '@playwright/test';

test('le formulaire /account/coverage-update est visible avec les champs requis', async ({ page }) => {
  await page.goto('/account/coverage-update');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="regime_obligatoire"][value="regime_general"]')).toBeVisible();
  await expect(page.locator('input[name="mutuelle_amc"]')).toBeVisible();
  await expect(page.locator('input[name="mutuelle_numero_adherent"]')).toBeVisible();
  await expect(page.locator('input[name="tiers_payant"][value="true"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/account/coverage-update');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="regime_obligatoire"][value="regime_general"]').check();
  await page.locator('input[name="mutuelle_amc"]').fill('MGEN');
  await page.locator('input[name="mutuelle_numero_adherent"]').fill('123456789');
  await page.locator('input[name="tiers_payant"][value="false"]').check();
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/account/coverage-update');
});
