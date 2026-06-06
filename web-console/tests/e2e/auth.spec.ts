import { test, expect } from '@playwright/test';

test('la page /test/auth affiche les deux formulaires register et login', async ({ page }) => {
  await page.goto('/test/auth');
  await expect(page.locator('form#register-form input[name="email"]')).toBeVisible();
  await expect(page.locator('form#register-form input[name="password"]')).toBeVisible();
  await expect(page.locator('form#register-form input[name="accept_cgu"]')).toBeVisible();
  await expect(page.locator('form#register-form button[type="submit"]')).toBeVisible();
  await expect(page.locator('#register-result')).toBeVisible();
  await expect(page.locator('form#login-form input[name="email"]')).toBeVisible();
  await expect(page.locator('form#login-form input[name="password"]')).toBeVisible();
  await expect(page.locator('form#login-form button[type="submit"]')).toBeVisible();
  await expect(page.locator('#login-result')).toBeVisible();
  await expect(page.locator('#mfa-section')).toBeHidden();
});

test('register réussi affiche account_id et access_token (201)', async ({ page }) => {
  await page.route('**/v1/auth/register', route =>
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({
        account_id: 'acc-abc',
        access_token: 'tok-access',
        refresh_token: 'tok-refresh',
      }),
    }),
  );

  await page.goto('/test/auth');
  await page.locator('form#register-form input[name="email"]').fill('nouveau@example.com');
  await page.locator('form#register-form input[name="password"]').fill('MotDePasse123!');
  await page.locator('form#register-form input[name="accept_cgu"]').check();
  await page.locator('form#register-form button[type="submit"]').click();
  await expect(page.locator('#register-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#register-result')).toContainText('account_id');
  await expect(page.locator('#register-result')).toContainText('access_token');
});

test('login réussi affiche les tokens (200)', async ({ page }) => {
  await page.route('**/v1/auth/login', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        access_token: 'tok-access',
        refresh_token: 'tok-refresh',
        token_type: 'Bearer',
        expires_in: 900,
      }),
    }),
  );

  await page.goto('/test/auth');
  await page.locator('form#login-form input[name="email"]').fill('patient@example.com');
  await page.locator('form#login-form input[name="password"]').fill('MotDePasse123!');
  await page.locator('form#login-form button[type="submit"]').click();
  await expect(page.locator('#login-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#login-result')).toContainText('access_token');
  await expect(page.locator('#login-result')).toContainText('refresh_token');
});

test('login avec mfa_required révèle la section MFA', async ({ page }) => {
  await page.route('**/v1/auth/login', route =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'mfa_required' }),
    }),
  );

  await page.goto('/test/auth');
  await page.locator('form#login-form input[name="email"]').fill('pro@example.com');
  await page.locator('form#login-form input[name="password"]').fill('MotDePasse123!');
  await page.locator('form#login-form button[type="submit"]').click();
  await expect(page.locator('#mfa-section')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#login-result')).toContainText('MFA requis');
});
