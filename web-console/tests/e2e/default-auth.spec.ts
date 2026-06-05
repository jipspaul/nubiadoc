import { test, expect } from '@playwright/test';

// Header: {"alg":"HS256","typ":"JWT"} · Payload: {"email":"test@example.com"} · sig: fake
const TEST_JWT =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9' +
  '.eyJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20ifQ' +
  '.fakesig';

test.beforeEach(async ({ page, context }) => {
  // Middleware checks cookie; client guard checks localStorage — set both.
  await context.addCookies([{ name: 'nubia_jwt', value: TEST_JWT, url: 'http://localhost:4321' }]);
  await page.goto('/login');
  await page.evaluate((jwt) => localStorage.setItem('nubia_jwt', jwt), TEST_JWT);
  await page.goto('/app');
});

test('GET /app avec nubia_jwt — header affiche une chaîne non vide à l\'emplacement email', async ({ page }) => {
  const el = page.locator('#user-email');
  await expect(el).not.toBeEmpty();
  await expect(el).toContainText('test@example.com');
});

test('clic "Déconnexion" — JWT supprimé du localStorage et redirection vers /', async ({ page }) => {
  await page.getByRole('button', { name: /déconnexion/i }).click();
  await expect(page).toHaveURL('/');
  const jwt = await page.evaluate(() => localStorage.getItem('nubia_jwt'));
  expect(jwt).toBeNull();
});
