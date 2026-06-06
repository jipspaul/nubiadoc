import { test, expect } from '@playwright/test';

test('la page forgot affiche le champ email et le bouton Envoyer', async ({ page }) => {
  await page.goto('/auth/password/forgot');
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('la page reset affiche les champs mot de passe et confirmation', async ({ page }) => {
  await page.goto('/auth/password/reset?token=test-token');
  await expect(page.locator('input[name="new_password"]')).toBeVisible();
  await expect(page.locator('input[name="confirm_password"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /réinitialiser/i })).toBeVisible();
});

test('happy path : forgot → 204 puis reset → 204', async ({ page }) => {
  await page.route('**/v1/auth/password/forgot', route =>
    route.fulfill({ status: 204 }),
  );

  await page.goto('/auth/password/forgot');
  await page.locator('input[name="email"]').fill('user@example.com');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 204', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('Si cet email existe', { timeout: 5000 });

  await page.route('**/v1/auth/password/reset', route =>
    route.fulfill({ status: 204 }),
  );

  await page.goto('/auth/password/reset?token=valid-reset-token');
  await page.locator('input[name="new_password"]').fill('NewPassword1!');
  await page.locator('input[name="confirm_password"]').fill('NewPassword1!');
  await page.getByRole('button', { name: /réinitialiser/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 204', { timeout: 5000 });
});

test('token expiré → 410', async ({ page }) => {
  await page.route('**/v1/auth/password/reset', route =>
    route.fulfill({
      status: 410,
      contentType: 'application/json',
      body: JSON.stringify({
        type: 'https://nubia.health/errors/gone',
        title: 'Token expiré',
        status: 410,
        code: 'token_expired',
      }),
    }),
  );

  await page.goto('/auth/password/reset?token=expired-reset-token');
  await page.locator('input[name="new_password"]').fill('NewPassword1!');
  await page.locator('input[name="confirm_password"]').fill('NewPassword1!');
  await page.getByRole('button', { name: /réinitialiser/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 410', { timeout: 5000 });
});
