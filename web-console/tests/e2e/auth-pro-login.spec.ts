import { test, expect } from '@playwright/test';

test('la page /auth/pro/login affiche les champs email, password, cabinet_id et le bouton', async ({ page }) => {
  await page.goto('/auth/pro/login');
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="password"]')).toBeVisible();
  await expect(page.locator('input[name="cabinet_id"]')).toBeVisible();
  await expect(page.locator('form#login-form button[type="submit"]')).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
  await expect(page.locator('#decoded-section')).toBeHidden();
});

test('login pro réussi affiche HTTP 200, le token JSON, et le token décodé (cabinet_id + role)', async ({ page }) => {
  // JWT factice : header.payload.sig — payload = { cabinet_id UUID non-nil, role, kind }
  const cabinetUuid = 'a1b2c3d4-e5f6-4890-abcd-ef1234567890';
  const payload = { cabinet_id: cabinetUuid, role: 'practitioner', kind: 'pro', email: 'pro@example.com' };
  const fakeJwt = `eyJhbGciOiJub25lIn0.${btoa(JSON.stringify(payload)).replace(/=/g, '')}.sig`;

  await page.route('**/v1/auth/login', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        access_token: fakeJwt,
        refresh_token: 'tok-refresh',
        token_type: 'Bearer',
        expires_in: 900,
      }),
    }),
  );

  await page.goto('/auth/pro/login');
  await page.locator('input[name="email"]').fill('pro@example.com');
  await page.locator('input[name="password"]').fill('MotDePasse123!');
  await page.locator('input[name="cabinet_id"]').fill(cabinetUuid);
  await page.locator('form#login-form button[type="submit"]').click();

  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('access_token');
  await expect(page.locator('#decoded-section')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#decoded-cabinet-id')).toContainText(cabinetUuid);
  await expect(page.locator('#decoded-role')).toContainText('practitioner');
});

test('credentials invalides affichent une erreur HTTP sans révéler la section décodée', async ({ page }) => {
  await page.route('**/v1/auth/login', route =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'invalid_credentials', message: 'Email ou mot de passe incorrect.' }),
    }),
  );

  await page.goto('/auth/pro/login');
  await page.locator('input[name="email"]').fill('pro@example.com');
  await page.locator('input[name="password"]').fill('mauvais');
  await page.locator('input[name="cabinet_id"]').fill('cab-test-42');
  await page.locator('form#login-form button[type="submit"]').click();

  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#decoded-section')).toBeHidden();
});
