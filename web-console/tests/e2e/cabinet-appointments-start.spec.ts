import { test, expect } from '@playwright/test';

test('render: /test/cabinet/appointments/appt-1/start affiche le formulaire', async ({ page }) => {
  await page.goto('/test/cabinet/appointments/appt-1/start');
  await expect(page.locator('#h-start')).toBeVisible();
  await expect(page.locator('#access-token')).toBeVisible();
  await expect(page.locator('#appointment-id')).toBeVisible();
  await expect(page.locator('#btn-start')).toBeVisible();
  await expect(page.locator('#result-start')).toBeVisible();
});

test('happy path: POST /start → 200 affiche status et started_at', async ({ page }) => {
  await page.route('**/v1/cabinet/appointments/appt-1/start', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'in_progress',
        started_at: '2026-06-07T10:00:00Z',
      }),
    });
  });

  await page.goto('/test/cabinet/appointments/appt-1/start');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#appointment-id').fill('appt-1');
  await page.locator('#btn-start').click();
  await expect(page.locator('#result-start')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-start')).toContainText('in_progress');
  await expect(page.locator('#result-start')).toContainText('started_at');
});

test('error path: POST /start → 409 affiche le code erreur', async ({ page }) => {
  await page.route('**/v1/cabinet/appointments/appt-1/start', (route) => {
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ error: 'already_started' }),
    });
  });

  await page.goto('/test/cabinet/appointments/appt-1/start');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#appointment-id').fill('appt-1');
  await page.locator('#btn-start').click();
  await expect(page.locator('#result-start')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#result-start')).toContainText('already_started');
});
