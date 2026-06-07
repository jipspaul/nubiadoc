import { test, expect } from '@playwright/test';

test('le formulaire /test/messaging/conversation-read est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/messaging/conversation-read');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="conversation_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /post/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('appel réussi => 2xx affiché', async ({ page }) => {
  await page.route('**/v1/conversations/*/read', (route) => {
    route.fulfill({
      status: 204,
      body: '',
    });
  });

  await page.goto('/test/messaging/conversation-read');
  await page.locator('input[name="access_token"]').fill('valid-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /post/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 204', { timeout: 5000 });
});

test('token invalide => 401 affiché', async ({ page }) => {
  await page.route('**/v1/conversations/*/read', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized', title: 'Token invalide' }),
    });
  });

  await page.goto('/test/messaging/conversation-read');
  await page.locator('input[name="access_token"]').fill('invalid-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /post/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});

test('id invalide => 422 affiché', async ({ page }) => {
  await page.route('**/v1/conversations/*/read', (route) => {
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'validation_error', title: 'id invalide' }),
    });
  });

  await page.goto('/test/messaging/conversation-read');
  await page.locator('input[name="access_token"]').fill('valid-token');
  await page.locator('input[name="conversation_id"]').fill('not-a-uuid');
  await page.getByRole('button', { name: /post/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 422', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('validation_error');
});
