import { test, expect } from '@playwright/test';

test('le formulaire /auth/register se rend avec email, password, cgu_version et checkbox CGU', async ({ page }) => {
  await page.goto('/auth/register');
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="password"]')).toBeVisible();
  await expect(page.locator('input[name="cgu_version"]')).toBeVisible();
  await expect(page.locator('input[name="accept_cgu"]')).toBeVisible();
  await expect(page.locator('form#register-form button[type="submit"]')).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('inscription réussie affiche les tokens et account_id (201)', async ({ page }) => {
  await page.route('**/v1/auth/register', route =>
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({
        account_id: 'acc-123',
        access_token: 'access-token-abc',
        refresh_token: 'refresh-token-xyz',
      }),
    }),
  );

  await page.goto('/auth/register');
  await page.locator('input[name="email"]').fill('nouveau@example.com');
  await page.locator('input[name="password"]').fill('MotDePasse123!');
  await page.locator('input[name="accept_cgu"]').check();
  await page.locator('form#register-form button[type="submit"]').click();
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('account_id');
  await expect(page.locator('#result')).toContainText('access_token');
});

test('email déjà pris affiche le message email_taken (409)', async ({ page }) => {
  await page.route('**/v1/auth/register', route =>
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'email_taken', title: 'Email déjà utilisé', status: 409 }),
    }),
  );

  await page.goto('/auth/register');
  await page.locator('input[name="email"]').fill('existant@example.com');
  await page.locator('input[name="password"]').fill('MotDePasse123!');
  await page.locator('input[name="accept_cgu"]').check();
  await page.locator('form#register-form button[type="submit"]').click();
  await expect(page.locator('#result')).toContainText('Email déjà utilisé', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('409');
});

test('mot de passe faible affiche une erreur de validation (422)', async ({ page }) => {
  await page.route('**/v1/auth/register', route =>
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({
        code: 'validation_error',
        status: 422,
        detail: 'Le mot de passe ne respecte pas la politique de sécurité.',
        errors: [{ field: 'password', rule: 'password_policy' }],
      }),
    }),
  );

  await page.goto('/auth/register');
  await page.locator('input[name="email"]').fill('test@example.com');
  await page.locator('input[name="password"]').fill('faible');
  await page.locator('input[name="accept_cgu"]').check();
  await page.locator('form#register-form button[type="submit"]').click();
  await expect(page.locator('#result')).toContainText('422', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('Validation');
});

test('CGU non acceptées affiche le message cgu_required (422)', async ({ page }) => {
  await page.route('**/v1/auth/register', route =>
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'cgu_required', status: 422, title: 'CGU non acceptées' }),
    }),
  );

  await page.goto('/auth/register');
  await page.locator('input[name="email"]').fill('test@example.com');
  await page.locator('input[name="password"]').fill('MotDePasse123!');
  await page.locator('input[name="accept_cgu"]').check();
  await page.locator('form#register-form button[type="submit"]').click();
  await expect(page.locator('#result')).toContainText('CGU', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('422');
});
