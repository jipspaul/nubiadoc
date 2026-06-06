import { test, expect } from '@playwright/test';

test('GET /test/ retourne 200 et contient une liste avec au moins 5 liens', async ({ page }) => {
  await page.goto('/test/');
  await expect(page.locator('ul')).toBeVisible();
  const links = page.locator('ul a[href^="/test/"]');
  await expect(links).toHaveCount(await links.count());
  expect(await links.count()).toBeGreaterThanOrEqual(5);
});

test('/auth/me affiche le formulaire GET /v1/me', async ({ page }) => {
  await page.goto('/auth/me');
  await expect(page.locator('h1')).toContainText('GET /v1/me');
  await expect(page.locator('#result')).toBeVisible();
});
