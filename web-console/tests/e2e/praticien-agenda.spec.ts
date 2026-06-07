import { test, expect } from '@playwright/test';

test('render — /praticien/agenda affiche le titre et les sections', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/praticien/agenda');
  await expect(page.getByRole('heading', { name: 'Agenda praticien', level: 1 })).toBeVisible();
  await expect(page.locator('#form-agenda')).toBeVisible();
  await expect(page.locator('#form-create')).toBeVisible();
});

test('error path — GET /v1/cabinet/agenda répond 401 affiche HTTP 401', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/agenda**', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });
  await page.goto('/praticien/agenda');
  await page.locator('input[name="date"]').fill('2026-06-07');
  await page.locator('#form-agenda button[type="submit"]').click();
  await expect(page.locator('#result-agenda')).toContainText('HTTP 401', { timeout: 5000 });
});
