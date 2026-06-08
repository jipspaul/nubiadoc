import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/rdv/[id] affiche le titre et l\'état de chargement', async ({ page }) => {
  // Block API so loading stays visible
  await page.route('**/v1/appointments/**', (route) => new Promise(() => {}));
  await page.goto('/patient/rdv/appt-001');
  await expect(page.getByRole('heading', { name: /détail du rendez-vous/i })).toBeVisible();
  await expect(page.locator('#rdv-loading')).toBeVisible();
});

// ─── happy path — RDV chargé ───────────────────────────────────────────────

test('happy path — RDV chargé : carte et actions visibles', async ({ page }) => {
  await page.route('**/v1/appointments/appt-001', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'appt-001',
        status: 'confirmed',
        scheduled_at: '2026-07-10T09:00:00Z',
        provider_id: 'prov-123',
      }),
    }),
  );

  await page.goto('/patient/rdv/appt-001');

  await expect(page.locator('#rdv-card')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#rdv-loading')).toBeHidden();
  await expect(page.locator('#rdv-status-badge')).toContainText('confirmed');
  await expect(page.locator('#actions-section')).toBeVisible();
});

// ─── error path — API 404 ─────────────────────────────────────────────────

test('error path — API 404 : message d\'erreur affiché, carte masquée', async ({ page }) => {
  await page.route('**/v1/appointments/appt-404', (route) =>
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found' }),
    }),
  );

  await page.goto('/patient/rdv/appt-404');

  await expect(page.locator('#rdv-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#rdv-card')).toBeHidden();
});
