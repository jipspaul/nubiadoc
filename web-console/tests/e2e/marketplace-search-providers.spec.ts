import { test, expect } from '@playwright/test';

test('la page /test/marketplace/search-providers affiche le formulaire', async ({ page }) => {
  await page.goto('/test/marketplace/search-providers');
  await expect(page.locator('#search-form')).toBeVisible();
  await expect(page.locator('button[type="submit"]')).toBeVisible();
});

test('GET /v1/search/providers retourne HTTP 200', async ({ page }) => {
  await page.goto('/test/marketplace/search-providers');
  await page.click('button[type="submit"]');
  await expect(page.locator('#status-badge')).toBeVisible();
  await expect(page.locator('#status-badge')).toContainText('200');
});
