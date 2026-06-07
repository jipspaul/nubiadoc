import { test, expect } from '@playwright/test';

test('la page /test/marketplace/search-slots affiche le formulaire', async ({ page }) => {
  await page.goto('/test/marketplace/search-slots');
  await expect(page.locator('#search-form')).toBeVisible();
  await expect(page.locator('button[type="submit"]')).toBeVisible();
});

test('GET /v1/search/slots retourne HTTP 200', async ({ page }) => {
  await page.goto('/test/marketplace/search-slots');
  await page.click('button[type="submit"]');
  await expect(page.locator('#status-badge')).toBeVisible();
  await expect(page.locator('#status-badge')).toContainText('200');
});
