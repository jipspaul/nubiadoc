import { test, expect } from '@playwright/test';

test('la page /test/messaging/cabinet-conversations affiche le formulaire token et le bouton GET', async ({ page }) => {
  await page.goto('/test/messaging/cabinet-conversations');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /^GET$/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('GET /v1/cabinet/conversations retourne 200 et les conversations urgentes sont marquées', async ({ page }) => {
  await page.route('**/v1/cabinet/conversations', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: '00000000-0000-0000-0000-000000000001',
          patient_name: 'Martin Dupont',
          last_message_at: '2026-06-01T10:00:00Z',
          unread_count: 2,
          triage_flag: true,
        },
        {
          id: '00000000-0000-0000-0000-000000000002',
          patient_name: 'Julie Bernard',
          last_message_at: '2026-05-30T08:30:00Z',
          unread_count: 0,
          triage_flag: false,
        },
      ]),
    });
  });

  await page.goto('/test/messaging/cabinet-conversations');
  await page.locator('input[name="access_token"]').fill('pro-access-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#conversations-list')).toBeVisible();
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"]')).toBeVisible();
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"]')).toContainText('Martin Dupont');
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"] [data-urgent]')).toBeVisible();
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000002"]')).toContainText('Julie Bernard');
});

test('token patient (403) => message d\'erreur affiché dans #result', async ({ page }) => {
  await page.route('**/v1/cabinet/conversations', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/test/messaging/cabinet-conversations');
  await page.locator('input[name="access_token"]').fill('patient-access-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('forbidden');
});

test('token invalide (401) => affiché dans #result', async ({ page }) => {
  await page.route('**/v1/cabinet/conversations', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/test/messaging/cabinet-conversations');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});
