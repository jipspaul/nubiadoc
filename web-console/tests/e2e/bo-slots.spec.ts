import { test, expect } from '@playwright/test';

// ── /cabinet/slots/create ────────────────────────────────────────────────────

test('render — /cabinet/slots/create affiche le formulaire POST', async ({ page }) => {
  await page.goto('/cabinet/slots/create');
  await expect(page.locator('#slots-create-form input[name="access_token"]')).toBeVisible();
  await expect(page.locator('#slots-create-form input[name="practitioner_id"]')).toBeVisible();
  await expect(page.locator('#slots-create-form input[name="starts_at"]')).toBeVisible();
  await expect(page.locator('#slots-create-form input[name="ends_at"]')).toBeVisible();
  await expect(page.locator('#slots-create-form select[name="status"]')).toBeVisible();
  await expect(page.locator('#slots-create-form button[type="submit"]')).toBeVisible();
  await expect(page.locator('#create-result')).toBeVisible();
});

test('happy path — POST /v1/cabinet/slots 201 créneau créé', async ({ page }) => {
  await page.route('**/v1/cabinet/slots', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ slot_id: '00000000-0000-0000-0000-000000000001', status: 'open' }),
    });
  });

  await page.goto('/cabinet/slots/create');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.locator('input[name="practitioner_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('input[name="starts_at"]').fill('2026-06-10T09:00');
  await page.locator('input[name="ends_at"]').fill('2026-06-10T09:30');
  await page.locator('button[type="submit"]').click();
  await expect(page.locator('#create-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#create-result')).toContainText('slot_id');
});

test('error path — POST /v1/cabinet/slots 409 slot_taken', async ({ page }) => {
  await page.route('**/v1/cabinet/slots', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'slot_taken' }),
    });
  });

  await page.goto('/cabinet/slots/create');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.locator('input[name="practitioner_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('input[name="starts_at"]').fill('2026-06-10T09:00');
  await page.locator('input[name="ends_at"]').fill('2026-06-10T09:30');
  await page.locator('button[type="submit"]').click();
  await expect(page.locator('#create-result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#create-result')).toContainText('slot_taken');
});

// ── /cabinet/slots (index — PATCH / PUT online / DELETE) ────────────────────

test('render — /cabinet/slots affiche les trois formulaires', async ({ page }) => {
  await page.goto('/cabinet/slots');
  await expect(page.locator('#slots-patch-form input[name="slot_id"]')).toBeVisible();
  await expect(page.locator('#slots-online-form select[name="online"]')).toBeVisible();
  await expect(page.locator('#slots-delete-form input[name="slot_id"]')).toBeVisible();
  await expect(page.locator('#patch-result')).toBeVisible();
  await expect(page.locator('#online-result')).toBeVisible();
  await expect(page.locator('#delete-result')).toBeVisible();
});

test('happy path — PUT /v1/cabinet/slots/{id}/online 200 toggle exposé', async ({ page }) => {
  await page.route('**/v1/cabinet/slots/*/online', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ slot_id: '00000000-0000-0000-0000-000000000001', online: true }),
    });
  });

  await page.goto('/cabinet/slots');
  await page.locator('#slots-online-form input[name="access_token"]').fill('pro-token');
  await page.locator('#slots-online-form input[name="slot_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('#slots-online-form select[name="online"]').selectOption('true');
  await page.locator('#slots-online-form button[type="submit"]').click();
  await expect(page.locator('#online-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#online-result')).toContainText('online');
});

test('happy path — DELETE /v1/cabinet/slots/{id} 204 créneau supprimé', async ({ page }) => {
  await page.route('**/v1/cabinet/slots/**', (route) => {
    if (route.request().method() !== 'DELETE') { route.continue(); return; }
    route.fulfill({ status: 204 });
  });

  await page.goto('/cabinet/slots');
  await page.locator('#slots-delete-form input[name="access_token"]').fill('pro-token');
  await page.locator('#slots-delete-form input[name="slot_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('#slots-delete-form button[type="submit"]').click();
  await expect(page.locator('#delete-result')).toContainText('HTTP 204', { timeout: 5000 });
});
