import { test, expect } from '@playwright/test';

test('la page /test/marketplace/provider-detail affiche le formulaire', async ({ page }) => {
  await page.goto('/test/marketplace/provider-detail');
  await expect(page.locator('#provider-form')).toBeVisible();
  await expect(page.locator('#provider-id')).toBeVisible();
  await expect(page.locator('button[type="submit"]')).toBeVisible();
});

test('GET /v1/providers/{id} et /availability affichent un badge HTTP', async ({ page }) => {
  await page.goto('/test/marketplace/provider-detail');
  await page.fill('#provider-id', 'prov_test');
  await page.click('button[type="submit"]');
  await expect(page.locator('#profile-section')).toBeVisible();
  await expect(page.locator('#profile-status-badge')).toContainText('HTTP');
  await expect(page.locator('#availability-section')).toBeVisible();
  await expect(page.locator('#avail-status-badge')).toContainText('HTTP');
});
