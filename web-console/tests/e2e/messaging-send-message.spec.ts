import { test, expect } from '@playwright/test';

test('le formulaire /test/messaging/send-message est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/messaging/send-message');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="conversation_id"]')).toBeVisible();
  await expect(page.locator('textarea[name="body"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /post/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('POST message valide => 201 + message_id affiché', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ message_id: 'aaaaaaaa-0000-0000-0000-000000000001' }),
    });
  });

  await page.goto('/test/messaging/send-message');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('textarea[name="body"]').fill('Bonjour, ceci est un message de test.');
  await page.getByRole('button', { name: /post/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#message-id')).toContainText('aaaaaaaa-0000-0000-0000-000000000001');
});

test('conversation_id inexistant => 404 affiché', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found', title: 'Conversation introuvable' }),
    });
  });

  await page.goto('/test/messaging/send-message');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000099');
  await page.locator('textarea[name="body"]').fill('Message pour une conversation inexistante.');
  await page.getByRole('button', { name: /post/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 404', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('not_found');
});

test('token invalide => 401 affiché', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized', title: 'Token invalide' }),
    });
  });

  await page.goto('/test/messaging/send-message');
  await page.locator('input[name="access_token"]').fill('invalid-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('textarea[name="body"]').fill('Message avec token invalide.');
  await page.getByRole('button', { name: /post/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});
