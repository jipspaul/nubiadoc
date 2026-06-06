import { test, expect } from '@playwright/test';

test('la page /test/health affiche les deux sections health', async ({ page }) => {
  await page.goto('/test/health');
  await expect(page.locator('h2').first()).toContainText('/health');
  await expect(page.locator('#result-liveness')).toBeVisible();
  await expect(page.locator('#result-ready')).toBeVisible();
});

test('cliquer Tester sur /health affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/health');
  await page.locator('#btn-liveness').click();
  await expect(page.locator('#result-liveness')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
});
