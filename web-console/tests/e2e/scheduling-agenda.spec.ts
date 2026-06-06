import { test, expect } from '@playwright/test';

test('le formulaire /test/scheduling/agenda est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/scheduling/agenda');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="date"]')).toBeVisible();
  await expect(page.locator('select[name="view"]')).toBeVisible();
  await expect(page.locator('input[name="practitioner_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('200 — token pro valide retourne agenda avec slots', async ({ page }) => {
  await page.route('**/v1/cabinet/agenda**', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        practitioners: [{ id: '00000000-0000-0000-0000-000000000001', display: 'Dr Dupont' }],
        slots: [{ id: '00000000-0000-0000-0000-000000000002', practitioner_id: '00000000-0000-0000-0000-000000000001', starts_at: '2026-06-06T09:00:00Z', ends_at: '2026-06-06T09:30:00Z', status: 'confirmed', motif: 'consultation' }],
      }),
    });
  });

  await page.goto('/test/scheduling/agenda');
  await page.locator('input[name="access_token"]').fill('pro-access-token');
  await page.locator('input[name="date"]').fill('2026-06-06');
  await page.locator('select[name="view"]').selectOption('day');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('slots');
});

test('403 — token patient reçoit une erreur 403', async ({ page }) => {
  await page.route('**/v1/cabinet/agenda**', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/test/scheduling/agenda');
  await page.locator('input[name="access_token"]').fill('patient-access-token');
  await page.locator('input[name="date"]').fill('2026-06-06');
  await page.locator('select[name="view"]').selectOption('day');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 403', { timeout: 5000 });
});

test('401 — sans token reçoit une erreur 401', async ({ page }) => {
  await page.route('**/v1/cabinet/agenda**', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/test/scheduling/agenda');
  await page.locator('input[name="access_token"]').fill('invalid-token');
  await page.locator('input[name="date"]').fill('2026-06-06');
  await page.locator('select[name="view"]').selectOption('day');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
});
