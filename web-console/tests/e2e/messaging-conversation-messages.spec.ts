import { test, expect } from '@playwright/test';

test('la page /test/messaging/conversation-messages affiche le formulaire token, conversation_id et le bouton GET', async ({ page }) => {
  await page.goto('/test/messaging/conversation-messages');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="conversation_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /^GET$/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('GET 200 avec messages — la liste est rendue', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: 'msg-001',
          body: 'Bonjour, j\'ai une question.',
          sender_type: 'patient',
          created_at: '2026-06-01T10:00:00Z',
        },
        {
          id: 'msg-002',
          body: 'Bonjour, comment puis-je vous aider ?',
          sender_type: 'pro',
          created_at: '2026-06-01T10:05:00Z',
        },
      ]),
    });
  });

  await page.goto('/test/messaging/conversation-messages');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#conversation-messages-list')).toBeVisible();
  await expect(page.locator('[data-message-id="msg-001"]')).toBeVisible();
  await expect(page.locator('[data-message-id="msg-001"]')).toContainText('patient');
  await expect(page.locator('[data-message-id="msg-002"]')).toContainText('pro');
});

test('GET 401 — token invalide affiché dans #result', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/test/messaging/conversation-messages');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.locator('input[name="conversation_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});

test('GET 422 — id invalide, erreur de validation affichée dans #result', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unprocessable_entity', detail: 'invalid uuid' }),
    });
  });

  await page.goto('/test/messaging/conversation-messages');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="conversation_id"]').fill('not-a-valid-uuid');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 422', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unprocessable_entity');
});
