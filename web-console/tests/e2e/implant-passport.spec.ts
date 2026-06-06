import { test, expect } from '@playwright/test';

test('la page /implant-passport est rendue avec les éléments principaux', async ({ page }) => {
  await page.goto('/implant-passport');
  await expect(page.locator('h1')).toContainText('GET /v1/implant-passport');
  await expect(page.locator('input[name="access_token"]').first()).toBeVisible();
  await expect(page.getByRole('button', { name: /charger le passeport/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('le formulaire passeport avec token bidon affiche un résultat HTTP', async ({ page }) => {
  await page.goto('/implant-passport');
  await page.locator('input[name="access_token"]').first().fill('fake-access-token');
  await page.getByRole('button', { name: /charger le passeport/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/implant-passport');
});

test('le lien export PDF est visible sur la page', async ({ page }) => {
  await page.goto('/implant-passport');
  await expect(page.getByRole('button', { name: /obtenir le lien pdf/i })).toBeVisible();
  await expect(page.locator('#export-result')).toBeVisible();
});
