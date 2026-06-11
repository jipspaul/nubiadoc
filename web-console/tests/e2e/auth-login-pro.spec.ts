import { test, expect } from '@playwright/test';

const CABINET_UUID = 'a1b2c3d4-e5f6-4890-abcd-ef1234567890';
const API_BASE = 'http://localhost:38030';

function makeFakeJwt(role: string): string {
  const payload = { cabinet_id: CABINET_UUID, role, kind: 'pro' };
  return `eyJhbGciOiJub25lIn0.${btoa(JSON.stringify(payload)).replace(/=/g, '')}.sig`;
}

function loginResponse(jwt: string): string {
  return JSON.stringify({ access_token: jwt, refresh_token: 'r', token_type: 'Bearer', expires_in: 900 });
}

test('Cas 1 : login practitioner → cabinet_id non-nil + role practitioner dans le token décodé', async ({ page }) => {
  const jwt = makeFakeJwt('practitioner');
  await page.route('**/v1/auth/login', route =>
    route.fulfill({ status: 200, contentType: 'application/json', body: loginResponse(jwt) }),
  );

  await page.goto('/auth/pro/login');
  await page.locator('input[name="email"]').fill('practitioner@example.com');
  await page.locator('input[name="password"]').fill('Pass123!');
  await page.locator('input[name="cabinet_id"]').fill(CABINET_UUID);
  await page.locator('form#login-form button[type="submit"]').click();

  await expect(page.locator('#decoded-section')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#decoded-cabinet-id')).toContainText(CABINET_UUID);
  await expect(page.locator('#decoded-role')).toHaveText('practitioner');
});

test('Cas 2 : login secretary → cabinet_id non-nil + role secretary dans le token décodé', async ({ page }) => {
  const jwt = makeFakeJwt('secretary');
  await page.route('**/v1/auth/login', route =>
    route.fulfill({ status: 200, contentType: 'application/json', body: loginResponse(jwt) }),
  );

  await page.goto('/auth/pro/login');
  await page.locator('input[name="email"]').fill('secretary@example.com');
  await page.locator('input[name="password"]').fill('Pass123!');
  await page.locator('input[name="cabinet_id"]').fill(CABINET_UUID);
  await page.locator('form#login-form button[type="submit"]').click();

  await expect(page.locator('#decoded-section')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#decoded-cabinet-id')).toContainText(CABINET_UUID);
  await expect(page.locator('#decoded-role')).toHaveText('secretary');
});

test('Cas 3 : GET /v1/cabinet/agenda avec token pro → réponse API 200', async ({ page }) => {
  const jwt = makeFakeJwt('practitioner');
  await page.route('**/v1/auth/login', route =>
    route.fulfill({ status: 200, contentType: 'application/json', body: loginResponse(jwt) }),
  );
  await page.route('**/v1/cabinet/agenda**', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ practitioners: [], slots: [] }),
    }),
  );

  await page.goto('/auth/pro/login');
  await page.locator('input[name="email"]').fill('practitioner@example.com');
  await page.locator('input[name="password"]').fill('Pass123!');
  await page.locator('input[name="cabinet_id"]').fill(CABINET_UUID);
  await page.locator('form#login-form button[type="submit"]').click();
  await expect(page.locator('#decoded-section')).toBeVisible({ timeout: 5000 });

  const status = await page.evaluate(
    async ({ token, base }: { token: string; base: string }): Promise<number> => {
      const res = await fetch(`${base}/v1/cabinet/agenda`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      return res.status;
    },
    { token: jwt, base: API_BASE },
  );

  expect(status).toBe(200);
});
