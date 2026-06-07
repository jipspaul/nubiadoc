import { test, expect } from '@playwright/test';

test('le formulaire /test/messaging/conversation-send est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/messaging/conversation-send');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="conversation_id"]')).toBeVisible();
  await expect(page.locator('textarea[name="body"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /post/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('appel réussi => 201 + message_id affiché', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ message_id: 'bbbbbbbb-0000-0000-0000-000000000002' }),
    });
  });

  await page.goto('/test/messaging/conversation-send');
  await page.locator('input[name="access_token"]').fill('valid-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('textarea[name="body"]').fill('Bonjour, test envoi message.');
  await page.getByRole('button', { name: /post/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#message-id')).toContainText('bbbbbbbb-0000-0000-0000-000000000002');
});

test('token invalide => 401 affiché', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized', title: 'Token invalide' }),
    });
  });

  await page.goto('/test/messaging/conversation-send');
  await page.locator('input[name="access_token"]').fill('invalid-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('textarea[name="body"]').fill('Message avec token invalide.');
  await page.getByRole('button', { name: /post/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});

test('corps manquant => 422 affiché', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'validation_error', title: 'body est requis' }),
    });
  });

  await page.goto('/test/messaging/conversation-send');
  await page.locator('input[name="access_token"]').fill('valid-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('textarea[name="body"]').fill('x');
  await page.getByRole('button', { name: /post/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 422', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('validation_error');
});
