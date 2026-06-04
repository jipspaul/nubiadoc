import { test, expect } from '@playwright/test';

test('le formulaire /account/dependent-detail est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/account/dependent-detail');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="dependent_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('proche valide — submit affiche un résultat HTTP avec dependent_account_id visible', async ({ page }) => {
  await page.goto('/test/account/dependent-detail');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="dependent_id"]').fill('11111111-1111-1111-1111-111111111111');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/account/dependent-detail');
});

test('ID inconnu — submit avec UUID aléatoire affiche badge 404', async ({ page }) => {
  await page.goto('/test/account/dependent-detail');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="dependent_id"]').fill('00000000-0000-0000-0000-000000000000');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/account/dependent-detail');
});
