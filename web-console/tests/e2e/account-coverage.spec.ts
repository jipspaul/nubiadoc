import { test, expect } from '@playwright/test';

test('le formulaire /account/coverage est visible avec les champs requis', async ({ page }) => {
  await page.goto('/account/coverage');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/account/coverage');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/account/coverage');
});

// Tests PATCH — NSS masqué + formulaire mutuelle
test('/account/coverage — formulaire PATCH visible, NSS masqué (type=password)', async ({ page }) => {
  await page.goto('/account/coverage');
  const nssInput = page.locator('input[name="nss"]');
  await expect(nssInput).toBeVisible();
  await expect(nssInput).toHaveAttribute('type', 'password');
  await expect(page.locator('input[name="mutuelle_amc"]')).toBeVisible();
  await expect(page.locator('input[name="mutuelle_numero_adherent"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /patch/i })).toBeVisible();
  await expect(page.locator('#result-patch')).toBeVisible();
});

test('/account/coverage — PATCH avec credentials bidon affiche un résultat', async ({ page }) => {
  await page.goto('/account/coverage');
  await page.locator('input[name="access_token_patch"]').fill('fake-token');
  await page.locator('input[name="regime_obligatoire"][value="regime_general"]').check();
  await page.locator('input[name="mutuelle_amc"]').fill('MGEN');
  await page.locator('input[name="mutuelle_numero_adherent"]').fill('123456789');
  await page.locator('input[name="tiers_payant"][value="false"]').check();
  await page.getByRole('button', { name: /patch/i }).click();
  await expect(page.locator('#result-patch')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/account/coverage');
});
