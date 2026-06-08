import { test, expect } from '@playwright/test';

test('render — /secretary/agenda affiche le titre et les six sections', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/agenda');
  await expect(page.getByRole('heading', { name: 'Agenda — gestion des RDV et créneaux', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Confirmer un RDV/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Créer un créneau/i })).toBeVisible();
  await expect(page.locator('#form-confirm')).toBeVisible();
  await expect(page.locator('#form-create-slot')).toBeVisible();
  await expect(page.locator('#result-confirm')).toBeVisible();
  await expect(page.locator('#result-create-slot')).toBeVisible();
});

test('happy path — confirme un RDV et affiche HTTP 200 dans le badge', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/appointments/*/confirm', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: '00000000-0000-0000-0000-000000000001',
        status: 'confirmed',
      }),
    });
  });
  await page.goto('/secretary/agenda');
  await page.locator('#form-confirm input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('#form-confirm button[type="submit"]').click();
  await expect(page.locator('#badge-confirm')).toContainText('200', { timeout: 5000 });
  await expect(page.locator('#result-confirm')).toContainText('confirmed');
});

test('error path — la confirmation d\'un RDV affiche HTTP 404 si le RDV est introuvable', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/appointments/*/confirm', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found' }),
    });
  });
  await page.goto('/secretary/agenda');
  await page.locator('#form-confirm input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000099');
  await page.locator('#form-confirm button[type="submit"]').click();
  await expect(page.locator('#badge-confirm')).toContainText('404', { timeout: 5000 });
  await expect(page.locator('#result-confirm')).toContainText('not_found');
});
