import { test, expect } from '@playwright/test';

test('la page /appointments/book est visible avec les champs requis', async ({ page }) => {
  await page.goto('/appointments/book');
  await expect(page.locator('h1')).toBeVisible();
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="provider_id"]')).toBeVisible();
  await expect(page.locator('input[name="motif"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /chercher les créneaux/i })).toBeVisible();
  // step 2 est caché initialement
  await expect(page.locator('#step-2')).toBeHidden();
});

test('happy path : créneaux chargés → sélection → POST 201 → confirmation affichée', async ({ page }) => {
  // Mock GET /v1/providers/:id/availability
  await page.route('**/v1/providers/**', (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: [
            { slot_id: 'slot-001', starts_at: '2026-07-10T09:00:00Z', ends_at: '2026-07-10T09:30:00Z' },
            { slot_id: 'slot-002', starts_at: '2026-07-10T10:00:00Z', ends_at: '2026-07-10T10:30:00Z' },
          ],
        }),
      });
    } else {
      route.continue();
    }
  });

  // Mock POST /v1/appointments
  await page.route('**/v1/appointments', (route) => {
    if (route.request().method() === 'POST') {
      route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({ appointment_id: 'appt-abc', status: 'confirmed' }),
      });
    } else {
      route.continue();
    }
  });

  await page.goto('/appointments/book');
  await page.locator('input[name="access_token"]').fill('tok-test');
  await page.locator('input[name="provider_id"]').fill('prov-001');
  await page.locator('input[name="motif"]').fill('détartrage');
  await page.getByRole('button', { name: /chercher les créneaux/i }).click();

  // Step 2 apparaît avec les créneaux
  await expect(page.locator('#step-2')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('.slot-btn').first()).toBeVisible();

  // Sélectionner le premier créneau
  await page.locator('.slot-btn').first().click();
  await expect(page.getByRole('button', { name: /réserver ce créneau/i })).toBeEnabled();

  // Réserver
  await page.getByRole('button', { name: /réserver ce créneau/i }).click();

  // Confirmation affichée
  await expect(page.locator('#step-3')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#confirmation-msg')).toContainText('appt-abc');
  await expect(page.locator('#confirmation-msg')).toContainText('confirmed');
  await expect(page.locator('#book-result')).toContainText('HTTP 201');
});

test('créneau indisponible : POST 409 slot_taken → message d\'erreur affiché', async ({ page }) => {
  await page.route('**/v1/providers/**', (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: [
            { slot_id: 'slot-taken', starts_at: '2026-07-10T09:00:00Z' },
          ],
        }),
      });
    } else {
      route.continue();
    }
  });

  await page.route('**/v1/appointments', (route) => {
    if (route.request().method() === 'POST') {
      route.fulfill({
        status: 409,
        contentType: 'application/json',
        body: JSON.stringify({ code: 'slot_taken', title: 'Créneau pris' }),
      });
    } else {
      route.continue();
    }
  });

  await page.goto('/appointments/book');
  await page.locator('input[name="access_token"]').fill('tok-test');
  await page.locator('input[name="provider_id"]').fill('prov-002');
  await page.locator('input[name="motif"]').fill('consultation');
  await page.getByRole('button', { name: /chercher les créneaux/i }).click();

  await expect(page.locator('#step-2')).toBeVisible({ timeout: 5000 });
  await page.locator('.slot-btn').first().click();
  await page.getByRole('button', { name: /réserver ce créneau/i }).click();

  await expect(page.locator('#step-3')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#confirmation-msg')).toContainText('Créneau indisponible');
  await expect(page.locator('#book-result')).toContainText('HTTP 409');
  await expect(page.locator('#book-result')).toContainText('slot_taken');
});
