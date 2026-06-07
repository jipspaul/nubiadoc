import { test, expect } from '@playwright/test';

test('la page /test/treatment-plans/implant-passport est rendue avec les éléments principaux', async ({ page }) => {
  await page.goto('/test/treatment-plans/implant-passport');
  await expect(page.locator('h1')).toContainText('GET /v1/implant-passport');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /charger/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('submit avec token bidon affiche un résultat HTTP ou erreur réseau', async ({ page }) => {
  await page.goto('/test/treatment-plans/implant-passport');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.getByRole('button', { name: /charger/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/treatment-plans/implant-passport');
});
