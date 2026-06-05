import { test, expect } from '@playwright/test';

// Header: {"alg":"HS256","typ":"JWT"} · Payload: {"email":"test@example.com"} · sig: fake
const TEST_JWT =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9' +
  '.eyJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20ifQ' +
  '.fakesig';

test.beforeEach(async ({ page, context }) => {
  await context.addCookies([{ name: 'nubia_jwt', value: TEST_JWT, url: 'http://localhost:4321' }]);
  await page.goto('/login');
  await page.evaluate((jwt) => localStorage.setItem('nubia_jwt', jwt), TEST_JWT);
});

test('GET /app avec JWT — page 200, "Mon compte" et "Ma mutuelle" présents dans le DOM', async ({ page }) => {
  const response = await page.goto('/app');
  expect(response?.status()).toBe(200);
  await expect(page.getByRole('heading', { name: 'Mon compte' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Ma mutuelle' })).toBeVisible();
});

test('clic sur la carte "Mon compte" — URL se termine par /app/account', async ({ page }) => {
  await page.route('**/v1/account/me', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ email: 'test@example.com', nom: '', telephone: '' }),
    }),
  );
  await page.goto('/app');
  await page.getByRole('link', { name: /Mon compte/ }).click();
  await expect(page).toHaveURL(/\/app\/account$/);
});
