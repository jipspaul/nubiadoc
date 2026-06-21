import { test, expect } from '@playwright/test';
import { secretaryUser } from './fixtures/users';

function makeSecretaryJwt(): string {
  const payload = {
    email: secretaryUser.email,
    kind: 'pro',
    role: 'secretary',
    cabinet_id: secretaryUser.cabinet_id,
  };
  return `eyJhbGciOiJub25lIn0.${btoa(JSON.stringify(payload)).replace(/=/g, '')}.sig`;
}

test('smoke — login secrétariat puis dashboard chargé (happy path)', async ({ page }) => {
  const jwt = makeSecretaryJwt();

  // Intercept POST /v1/auth/login → 200 avec le JWT fixture secrétaire
  await page.route('**/v1/auth/login', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        access_token: jwt,
        refresh_token: 'refresh-fixture',
        token_type: 'Bearer',
        expires_in: 900,
      }),
    }),
  );

  await page.route('**/v1/cabinet/appointments**', route => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/cabinet/agenda**', route => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/cabinet/waiting-room', route => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });

  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill(secretaryUser.email);
  await page.locator('input[name="password"]').fill(secretaryUser.password);
  await page.locator('form#login-form button[type="submit"]').click();

  await page.waitForURL(/\/app/, { timeout: 5000 });

  await page.goto('/secretary/dashboard');
  await expect(page.getByRole('heading', { name: 'Tableau de bord secrétaire', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Rendez-vous du jour/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /File d'attente/i })).toBeVisible();
});
