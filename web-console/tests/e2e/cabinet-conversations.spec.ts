import { test, expect } from '@playwright/test';

test('render — /test/cabinet/conversations affiche le formulaire', async ({ page }) => {
  await page.goto('/test/cabinet/conversations');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /^GET$/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path — GET 200 affiche la liste des conversations', async ({ page }) => {
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

  await page.goto('/test/cabinet/conversations');
  await page.locator('input[name="access_token"]').fill('pro-access-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#conversations-list')).toBeVisible();
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"]')).toContainText('Martin Dupont');
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000001"] [data-urgent]')).toBeVisible();
  await expect(page.locator('[data-conversation-id="00000000-0000-0000-0000-000000000002"]')).toContainText('Julie Bernard');
});

test('error path — GET 401 affiche HTTP 401 dans #result', async ({ page }) => {
  await page.route('**/v1/cabinet/conversations', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/test/cabinet/conversations');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});

test('error path — GET 422 affiche HTTP 422 dans #result', async ({ page }) => {
  await page.route('**/v1/cabinet/conversations', (route) => {
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'validation_error', details: 'invalid query param' }),
    });
  });

  await page.goto('/test/cabinet/conversations');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 422', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('validation_error');
});
