import { test, expect } from '@playwright/test';

test('le formulaire /auth/login se rend avec email, password et section MFA cachée', async ({ page }) => {
  await page.goto('/auth/login');
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="password"]')).toBeVisible();
  await expect(page.locator('#mfa-section')).toBeHidden();
  await expect(page.locator('form#login-form button[type="submit"]')).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('mauvais mot de passe affiche un résultat d\'erreur générique', async ({ page }) => {
  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill('fake@example.com');
  await page.locator('input[name="password"]').fill('wrongpassword');
  await page.locator('form#login-form button[type="submit"]').click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/auth/login');
});

test('réponse mfa_required révèle la section MFA', async ({ page }) => {
  await page.route('**/v1/auth/login', route =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'mfa_required', message: 'MFA required' }),
    }),
  );

  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill('pro@example.com');
  await page.locator('input[name="password"]').fill('CorrectPassword1!');
  await page.locator('form#login-form button[type="submit"]').click();
  await expect(page.locator('#mfa-section')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#result')).toContainText('MFA requis');
});

test('email inconnu affiche une erreur générique', async ({ page }) => {
  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill('unknown@nowhere.invalid');
  await page.locator('input[name="password"]').fill('anypassword');
  await page.locator('form#login-form button[type="submit"]').click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/auth/login');
});
