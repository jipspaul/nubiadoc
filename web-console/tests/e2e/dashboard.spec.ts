import { test, expect } from '@playwright/test';

test('GET /dashboard — page 200, formulaire et #result visibles', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: /GET \/v1\/dashboard/i })).toBeVisible();
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /charger le dashboard/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('submit avec token fictif — statut HTTP visible dans #result', async ({ page }) => {
  await page.route('**/v1/dashboard', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        next_appointment: { id: 'abc', starts_at: '2026-07-01T09:00:00Z', motif: 'bilan' },
        to_sign: [{ quote_id: 'q1', label: 'Devis implant' }],
        unread_messages: 2,
      }),
    }),
  );

  await page.goto('/dashboard');
  await page.locator('input[name="access_token"]').fill('fake-token');
  await page.getByRole('button', { name: /charger le dashboard/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.getByRole('heading', { name: /prochain rendez-vous/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /documents à signer/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /messages non lus/i })).toBeVisible();
});

test('GET /appointments — page 200, formulaires liste et prise de RDV visibles', async ({ page }) => {
  await page.goto('/appointments');
  await expect(page.getByRole('heading', { name: /liste des rendez-vous/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /prendre un rendez-vous/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /charger les rdv/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /prendre rdv/i })).toBeVisible();
});

test('POST /appointments — confirmation visible après 201', async ({ page }) => {
  await page.route('**/v1/appointments', (route) => {
    if (route.request().method() === 'POST') {
      route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({ appointment_id: 'appt-123', status: 'confirmed' }),
      });
    } else {
      route.continue();
    }
  });

  await page.goto('/appointments');
  const bookSection = page.locator('section').filter({ hasText: /prendre un rendez-vous/i });
  await bookSection.locator('input[name="access_token"]').fill('fake-token');
  await bookSection.locator('input[name="provider_id"]').fill('00000000-0000-0000-0000-000000000001');
  await bookSection.locator('input[name="motif"]').fill('bilan annuel');
  await page.getByRole('button', { name: /prendre rdv/i }).click();
  await expect(page.locator('#book-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#book-confirmation')).toContainText('appt-123');
});
