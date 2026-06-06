import { test, expect } from '@playwright/test';

test('le formulaire /auth/refresh est visible avec le champ et le bouton', async ({ page }) => {
  await page.goto('/test/auth/refresh');
  await expect(page.locator('input[name="refresh_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('submit avec token bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/auth/refresh');
  await page.locator('input[name="refresh_token"]').fill('fake-refresh-token');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/auth/refresh');
});

test('happy path : refresh valide → 200 + nouveaux tokens affichés', async ({ page }) => {
  await page.route('**/v1/auth/refresh', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        access_token: 'new-access-token-abc',
        refresh_token: 'new-refresh-token-xyz',
        token_type: 'Bearer',
        expires_in: 900,
      }),
    }),
  );

  await page.goto('/test/auth/refresh');
  await page.locator('input[name="refresh_token"]').fill('valid-refresh-token');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('access_token');
  await expect(page.locator('#result')).toContainText('refresh_token');
});

test('refresh token expiré → 401', async ({ page }) => {
  await page.route('**/v1/auth/refresh', route =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({
        type: 'https://nubia.health/errors/unauthenticated',
        title: 'Token expiré',
        status: 401,
        code: 'unauthenticated',
      }),
    }),
  );

  await page.goto('/test/auth/refresh');
  await page.locator('input[name="refresh_token"]').fill('expired-refresh-token');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
});

test('rejeu d\'un refresh déjà utilisé → 401 (replay detection)', async ({ page }) => {
  await page.route('**/v1/auth/refresh', route =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({
        type: 'https://nubia.health/errors/unauthenticated',
        title: 'Token déjà utilisé',
        status: 401,
        code: 'unauthenticated',
      }),
    }),
  );

  await page.goto('/test/auth/refresh');
  await page.locator('input[name="refresh_token"]').fill('already-used-refresh-token');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
});
