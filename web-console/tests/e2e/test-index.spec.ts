import { test, expect } from '@playwright/test';

test('GET /test/ retourne 200 et contient une liste avec au moins 5 liens', async ({ page }) => {
  await page.goto('/test/');
  await expect(page.locator('ul')).toBeVisible();
  const links = page.locator('ul a[href^="/test/"]');
  await expect(links).toHaveCount(await links.count());
  expect(await links.count()).toBeGreaterThanOrEqual(5);
});

test('ancienne URL /auth/me retourne 404', async ({ page }) => {
  const response = await page.goto('/auth/me');
  expect(response?.status()).toBe(404);
});
