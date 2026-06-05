import { test, expect } from '@playwright/test';

test('la page /marketplace/professions affiche un tableau visible', async ({ page }) => {
  await page.goto('/marketplace/professions');
  await expect(page.locator('table')).toBeVisible();
});

test('le tableau /marketplace/professions contient une profession (dentiste ou orthodontiste)', async ({ page }) => {
  await page.goto('/marketplace/professions');
  await expect(page.locator('td')).toContainText(/dentiste|orthodontiste/i, { timeout: 8000 });
});
