import { test, expect } from '@playwright/test';

// --- /cabinet/agenda ---

test('render: /cabinet/agenda affiche le formulaire agenda', async ({ page }) => {
  await page.goto('/cabinet/agenda');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="date"]')).toBeVisible();
  await expect(page.locator('select[name="view"]')).toBeVisible();
  await expect(page.locator('input[name="practitioner_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#agenda-result')).toBeVisible();
});

test('happy path: /cabinet/agenda — token pro valide retourne agenda avec slots', async ({ page }) => {
  await page.route('**/v1/cabinet/agenda**', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        practitioners: [{ id: '00000000-0000-0000-0000-000000000001', display: 'Dr Dupont' }],
        slots: [{
          id: '00000000-0000-0000-0000-000000000002',
          practitioner_id: '00000000-0000-0000-0000-000000000001',
          starts_at: '2026-06-10T09:00:00Z',
          ends_at: '2026-06-10T09:30:00Z',
          status: 'confirmed',
          motif: 'consultation',
        }],
      }),
    });
  });

  await page.goto('/cabinet/agenda');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.locator('input[name="date"]').fill('2026-06-10');
  await page.locator('select[name="view"]').selectOption('day');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#agenda-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#agenda-result')).toContainText('slots');
});

test('error path: /cabinet/agenda — token invalide retourne 401', async ({ page }) => {
  await page.route('**/v1/cabinet/agenda**', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthenticated' }),
    });
  });

  await page.goto('/cabinet/agenda');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.locator('input[name="date"]').fill('2026-06-10');
  await page.locator('select[name="view"]').selectOption('day');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#agenda-result')).toContainText('HTTP 401', { timeout: 5000 });
});

// --- /cabinet/appointments ---

test('render: /cabinet/appointments affiche le formulaire liste RDV', async ({ page }) => {
  await page.goto('/cabinet/appointments');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('select[name="status"]')).toBeVisible();
  await expect(page.locator('input[name="date"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#list-result')).toBeVisible();
});

test('happy path: /cabinet/appointments — retourne liste RDV', async ({ page }) => {
  await page.route('**/v1/cabinet/appointments**', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: [{
          id: '00000000-0000-0000-0000-000000000010',
          status: 'confirmed',
          starts_at: '2026-06-10T10:00:00Z',
          motif: 'détartrage',
        }],
        page: { next_cursor: null, limit: 20 },
      }),
    });
  });

  await page.goto('/cabinet/appointments');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.locator('select[name="status"]').selectOption('confirmed');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#list-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#list-result')).toContainText('confirmed');
});

// --- /cabinet/appointments/[id] ---

test('render: /cabinet/appointments/:id affiche les trois formulaires', async ({ page }) => {
  await page.goto('/cabinet/appointments/00000000-0000-0000-0000-000000000001');
  await expect(page.locator('#get-form input[name="access_token"]')).toBeVisible();
  await expect(page.locator('#get-form input[name="appointment_id"]')).toBeVisible();
  await expect(page.locator('#confirm-form input[name="appointment_id"]')).toBeVisible();
  await expect(page.locator('#patch-form input[name="appointment_id"]')).toBeVisible();
  await expect(page.locator('#get-result')).toBeVisible();
  await expect(page.locator('#confirm-result')).toBeVisible();
  await expect(page.locator('#patch-result')).toBeVisible();
});

test('happy path confirm: POST /v1/cabinet/appointments/:id/confirm retourne 200', async ({ page }) => {
  await page.route('**/v1/cabinet/appointments/*/confirm', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ id: '00000000-0000-0000-0000-000000000001', status: 'confirmed' }),
    });
  });

  await page.goto('/cabinet/appointments/00000000-0000-0000-0000-000000000001');
  await page.locator('#confirm-form input[name="access_token"]').fill('pro-token');
  await page.locator('#confirm-form input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('#confirm-form').getByRole('button', { name: /post confirm/i }).click();
  await expect(page.locator('#confirm-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#confirm-result')).toContainText('confirmed');
});

test('happy path patch: PATCH /v1/cabinet/appointments/:id retourne 200', async ({ page }) => {
  await page.route('**/v1/cabinet/appointments/00000000-0000-0000-0000-000000000001', (route) => {
    if (route.request().method() === 'PATCH') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ id: '00000000-0000-0000-0000-000000000001', motif: 'bilan' }),
      });
    } else {
      route.continue();
    }
  });

  await page.goto('/cabinet/appointments/00000000-0000-0000-0000-000000000001');
  await page.locator('#patch-form input[name="access_token"]').fill('pro-token');
  await page.locator('#patch-form input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('#patch-form input[name="motif"]').fill('bilan');
  await page.locator('#patch-form').getByRole('button', { name: /patch/i }).click();
  await expect(page.locator('#patch-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#patch-result')).toContainText('bilan');
});
