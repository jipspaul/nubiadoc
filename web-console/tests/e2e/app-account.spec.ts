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

test('GET /app/account avec JWT — formulaire contient input[name=email]', async ({ page }) => {
  await page.route('**/v1/account/me', (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ email: 'test@example.com', nom: 'Dupont', telephone: '0600000000' }),
      });
    } else {
      route.continue();
    }
  });

  await page.goto('/app/account');
  await expect(page.locator('input[name="email"]')).toBeVisible({ timeout: 5000 });
});

test('submit du formulaire avec mock API 200 — toast "Informations mises à jour" visible', async ({ page }) => {
  await page.route('**/v1/account/me', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ email: 'test@example.com', nom: 'Dupont', telephone: '0600000000' }),
    }),
  );

  await page.goto('/app/account');
  await expect(page.locator('input[name="email"]')).toBeVisible({ timeout: 5000 });

  await page.locator('form#profile-form button[type="submit"]').click();
  await expect(page.locator('#toast')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#toast')).toContainText('Informations mises à jour');
});
