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

test('GET /app/coverage avec JWT — page 200, aucune erreur JS', async ({ page }) => {
  const jsErrors: Error[] = [];
  page.on('pageerror', (err) => jsErrors.push(err));

  const response = await page.goto('/app/coverage');
  expect(response?.status()).toBe(200);

  await page.waitForFunction(
    () => (document.getElementById('loading-msg') as HTMLElement | null)?.hidden === true,
    { timeout: 5000 },
  );

  expect(jsErrors).toHaveLength(0);
});

test('mock API { status: "active" } — affiche "active" et pas "Aucune mutuelle"', async ({ page }) => {
  await page.route('**/v1/account/coverage', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ status: 'active' }),
    }),
  );

  await page.goto('/app/coverage');
  await expect(page.locator('#coverage-status')).toContainText(/active|Actif/i, { timeout: 5000 });
  await expect(page.locator('#no-coverage')).toBeHidden();
});
