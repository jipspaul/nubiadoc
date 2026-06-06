import { test, expect } from '@playwright/test';

test('render — /cabinet/consultations/:id affiche le formulaire GET', async ({ page }) => {
  await page.goto('/cabinet/consultations/00000000-0000-0000-0000-000000000001');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="consultation_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#get-result')).toBeVisible();
});

test('happy path — GET 200 affiche le contexte clinique', async ({ page }) => {
  const consultationId = '00000000-0000-0000-0000-000000000001';
  await page.route(`**/v1/cabinet/consultations/${consultationId}`, (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: consultationId,
        appointment_id: 'appt-uuid-1',
        patient_id: 'patient-uuid-1',
        status: 'in_progress',
        ccam_codes: [],
        note: null,
        started_at: '2026-06-06T09:00:00Z',
      }),
    });
  });

  await page.goto(`/cabinet/consultations/${consultationId}`);
  await page.locator('input[name="access_token"]').fill('practitioner-token');
  await page.locator('input[name="consultation_id"]').fill(consultationId);
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#get-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#get-result')).toContainText(consultationId);
});

test('403 secretary — accès refusé affiché dans le résultat', async ({ page }) => {
  const consultationId = '00000000-0000-0000-0000-000000000002';
  await page.route(`**/v1/cabinet/consultations/${consultationId}`, (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto(`/cabinet/consultations/${consultationId}`);
  await page.locator('input[name="access_token"]').fill('secretary-token');
  await page.locator('input[name="consultation_id"]').fill(consultationId);
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#get-result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#get-result')).toContainText('forbidden');
});

test('404 inexistant — consultation introuvable affichée dans le résultat', async ({ page }) => {
  const consultationId = '00000000-0000-0000-0000-000000000000';
  await page.route(`**/v1/cabinet/consultations/${consultationId}`, (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found' }),
    });
  });

  await page.goto(`/cabinet/consultations/${consultationId}`);
  await page.locator('input[name="access_token"]').fill('practitioner-token');
  await page.locator('input[name="consultation_id"]').fill(consultationId);
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#get-result')).toContainText('HTTP 404', { timeout: 5000 });
  await expect(page.locator('#get-result')).toContainText('not_found');
});
