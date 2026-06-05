import { test, expect } from '@playwright/test';

test('la page /test/messaging/messages affiche le formulaire token, conversation_id et le bouton GET', async ({ page }) => {
  await page.goto('/test/messaging/messages');
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

  await page.goto('/test/messaging/messages');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="conversation_id"]').fill('conv-123');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#messages-list')).toBeVisible();
  await expect(page.locator('[data-message-id="msg-001"]')).toBeVisible();
  await expect(page.locator('[data-message-id="msg-001"]')).toContainText('patient');
  await expect(page.locator('[data-message-id="msg-001"]')).toContainText('Bonjour, j\'ai une question.');
  await expect(page.locator('[data-message-id="msg-002"]')).toContainText('pro');
});

test('GET 404 — erreur affichée dans #result', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found' }),
    });
  });

  await page.goto('/test/messaging/messages');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="conversation_id"]').fill('unknown-conv');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 404', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('not_found');
});

test('GET 401 — token invalide affiché dans #result', async ({ page }) => {
  await page.route('**/v1/conversations/*/messages', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/test/messaging/messages');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.locator('input[name="conversation_id"]').fill('conv-123');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});
