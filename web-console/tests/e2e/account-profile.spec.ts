import { test, expect } from '@playwright/test';

test('le formulaire /account/profile est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/account/profile');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/account/profile');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/account/profile');
});

// Tests pour la page /account/profile (GET + PATCH)
test('/account/profile — GET et PATCH visibles, formulaires rendus', async ({ page }) => {
  await page.goto('/account/profile');
  await expect(page.locator('input[name="access_token_get"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result-get')).toBeVisible();
  await expect(page.locator('input[name="access_token_patch"]')).toBeVisible();
  await expect(page.locator('input[name="first_name"]')).toBeVisible();
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="phone"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /patch/i })).toBeVisible();
  await expect(page.locator('#result-patch')).toBeVisible();
});

test('/account/profile — PATCH avec credentials bidon affiche un résultat', async ({ page }) => {
  await page.goto('/account/profile');
  await page.locator('input[name="access_token_patch"]').fill('fake-token');
  await page.locator('input[name="first_name"]').fill('Marie');
  await page.locator('input[name="last_name"]').fill('Dupont');
  await page.locator('input[name="email"]').fill('marie@example.com');
  await page.getByRole('button', { name: /patch/i }).click();
  await expect(page.locator('#result-patch')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/account/profile');
});

test('/account/profile — GET sans JWT affiche HTTP 401 ou erreur réseau', async ({ page }) => {
  await page.goto('/account/profile');
  await page.locator('input[name="access_token_get"]').fill('no-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result-get')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
});
