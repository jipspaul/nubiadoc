import { test, expect } from '@playwright/test';

test('render — /secretary/messagerie affiche le titre et la section conversations', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/messagerie');
  await expect(page.getByRole('heading', { name: 'Messagerie du cabinet', level: 1 })).toBeVisible();
  await expect(page.locator('#conv-status')).toBeVisible();
  await expect(page.locator('#conv-container')).toBeVisible();
});

test('happy path — affiche les conversations admin retournées par l\'API', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/conversations', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: '00000000-0000-0000-0000-000000000001',
          subject: 'Demande de RDV',
          last_message_at: '2026-06-01T10:00:00Z',
          unread_count: 2,
          scope: 'admin',
        },
        {
          id: '00000000-0000-0000-0000-000000000002',
          subject: 'Confirmation facture',
          last_message_at: '2026-05-30T08:30:00Z',
          unread_count: 0,
          scope: 'admin',
        },
      ]),
    });
  });
  await page.goto('/secretary/messagerie');
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"]')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"]')).toContainText('Demande de RDV');
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000002"]')).toContainText('Confirmation facture');
});

test('error path — affiche une erreur 403 si l\'API refuse l\'accès', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/conversations', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.goto('/secretary/messagerie');
  await expect(page.locator('#conv-status')).toContainText('403', { timeout: 5000 });
});
