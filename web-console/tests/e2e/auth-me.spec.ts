import { test, expect } from '@playwright/test';

test('le formulaire /auth/me est visible avec les champs requis', async ({ page }) => {
  await page.goto('/auth/me');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('une requête GET affiche le statut HTTP et la réponse JSON', async ({ page }) => {
  await page.route('**/v1/me', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        user_id: 'usr-test-001',
        email: 'test@example.com',
        kind: 'patient',
        account_id: 'acc-001',
      }),
    }),
  );

  await page.goto('/auth/me');
  await page.locator('input[name="access_token"]').fill('fake-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('usr-test-001');
  await expect(page.locator('#result')).toContainText('test@example.com');
});
