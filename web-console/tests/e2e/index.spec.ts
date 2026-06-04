import { test, expect } from '@playwright/test';

test('index page renders the title and the login link', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/.+/);
  await expect(page.getByRole('link', { name: /login/i })).toBeVisible();
});
