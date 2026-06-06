import { test, expect } from '@playwright/test';

test('render : la page /test/me affiche les trois sections', async ({ page }) => {
  await page.goto('/test/me');
  await expect(page.locator('#me-form')).toBeVisible();
  await expect(page.locator('#refresh-form')).toBeVisible();
  await expect(page.locator('#logout-form')).toBeVisible();
  await expect(page.locator('#me-result')).toBeVisible();
  await expect(page.locator('#refresh-result')).toBeVisible();
  await expect(page.locator('#logout-result')).toBeVisible();
});

test('happy path : GET /v1/me affiche le profil patient', async ({ page }) => {
  await page.route('**/v1/me', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        user_id: 'usr-test-001',
        email: 'test@example.com',
        kind: 'patient',
        account_id: 'acc-001',
        memberships: [],
      }),
    }),
  );

  await page.goto('/test/me');
  await page.locator('#access-token').fill('fake-access-token');
  await page.locator('#me-form button[type="submit"]').click();

  await expect(page.locator('#me-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#field-user_id')).toContainText('usr-test-001');
  await expect(page.locator('#field-email')).toContainText('test@example.com');
  await expect(page.locator('#field-kind')).toContainText('patient');
});

test('error path : refresh avec token invalide affiche HTTP 401', async ({ page }) => {
  await page.route('**/v1/auth/refresh', route =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({
        code: 'unauthenticated',
        status: 401,
        title: 'Token invalide ou expiré',
      }),
    }),
  );

  await page.goto('/test/me');
  await page.locator('#refresh-form input[name="refresh_token"]').fill('expired-refresh-token');
  await page.locator('#refresh-form button[type="submit"]').click();

  await expect(page.locator('#refresh-result')).toContainText('HTTP 401', { timeout: 5000 });
});

test('error path : logout révoque le token (204)', async ({ page }) => {
  await page.route('**/v1/auth/logout', route =>
    route.fulfill({ status: 204, body: '' }),
  );

  await page.goto('/test/me');
  await page.locator('#logout-form input[name="logout_access_token"]').fill('access-tok');
  await page.locator('#logout-form input[name="logout_refresh_token"]').fill('refresh-tok');
  await page.locator('#logout-form button[type="submit"]').click();

  await expect(page.locator('#logout-result')).toContainText('HTTP 204', { timeout: 5000 });
});
