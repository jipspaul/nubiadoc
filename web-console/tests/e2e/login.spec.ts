import { test, expect } from '@playwright/test';

test('login page renders form with a submit button', async ({ page }) => {
  await page.goto('/login');
  await expect(page.getByRole('button', { name: /envoyer|submit|login|connecter/i })).toBeVisible();
});

test('empty credentials: page stays on /login, result stays empty', async ({ page }) => {
  await page.goto('/login');
  // Native HTML5 required validation fires — JS handler is never called
  await page.getByRole('button', { name: /envoyer|submit|login|connecter/i }).click();
  await expect(page).toHaveURL('/login');
  await expect(page.locator('#result')).toBeEmpty();
});

test('invalid credentials: page stays on /login and result shows an error', async ({ page }) => {
  await page.goto('/login');
  await page.locator('input[name="email"]').fill('nobody@example.com');
  await page.locator('input[name="password"]').fill('wrongpassword123');
  await page.getByRole('button', { name: /envoyer|submit|login|connecter/i }).click();
  // Backend 401 or network unreachable: both code paths set class="error" on #result
  await expect(page.locator('#result')).toHaveClass(/error/, { timeout: 10_000 });
  await expect(page).toHaveURL('/login');
});
