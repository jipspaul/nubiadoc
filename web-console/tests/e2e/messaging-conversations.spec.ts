import { test, expect } from '@playwright/test';

test('la page /test/messaging/conversations affiche le formulaire token et le bouton GET', async ({ page }) => {
  await page.goto('/test/messaging/conversations');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /^GET$/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('GET /v1/conversations retourne 200 et la liste est rendue avec unread_count', async ({ page }) => {
  await page.route('**/v1/conversations', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: '00000000-0000-0000-0000-000000000001',
          cabinet_name: 'Cabinet Dupont',
          last_message_at: '2026-06-01T10:00:00Z',
          unread_count: 3,
        },
        {
          id: '00000000-0000-0000-0000-000000000002',
          cabinet_name: 'Cabinet Martin',
          last_message_at: '2026-05-30T08:30:00Z',
          unread_count: 0,
        },
      ]),
    });
  });

  await page.goto('/test/messaging/conversations');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#conversations-list')).toBeVisible();
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"]')).toBeVisible();
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"]')).toContainText('Cabinet Dupont');
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"] .conv-unread')).toContainText('3');
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000002"]')).toContainText('Cabinet Martin');
});

test('liste vide => message "Aucune conversation" affiché', async ({ page }) => {
  await page.route('**/v1/conversations', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([]),
    });
  });

  await page.goto('/test/messaging/conversations');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#conversations-list')).toBeVisible();
  await expect(page.locator('#list-items')).toContainText('Aucune conversation');
});

test('token invalide => 401 affiché dans #result', async ({ page }) => {
  await page.route('**/v1/conversations', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/test/messaging/conversations');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});
