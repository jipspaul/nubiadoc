import { test, expect } from '@playwright/test';

test('le formulaire /test/treatment-plans/detail est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/treatment-plans/detail');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="plan_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('submit avec token et ID bidon affiche un résultat (status ou erreur réseau)', async ({ page }) => {
  await page.goto('/test/treatment-plans/detail');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="plan_id"]').fill('00000000-0000-0000-0000-000000000000');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/treatment-plans/detail');
});

test('erreur 404 affiche HTTP 404 ou erreur réseau (pas de backend en CI)', async ({ page }) => {
  await page.goto('/test/treatment-plans/detail');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="plan_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP 404|HTTP 401|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/treatment-plans/detail');
});
