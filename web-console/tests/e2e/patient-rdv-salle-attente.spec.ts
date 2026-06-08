import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/rdv/[id]/salle-attente affiche le titre et l\'état de chargement', async ({ page }) => {
  // Block API so loading stays visible
  await page.route('**/v1/appointments/**', (route) => new Promise(() => {}));
  await page.goto('/patient/rdv/appt-001/salle-attente');
  await expect(page.getByRole('heading', { name: /salle d'attente/i })).toBeVisible();
  await expect(page.locator('#queue-loading')).toBeVisible();
});

// ─── happy path — position dans la file chargée ───────────────────────────

test('happy path — position chargée : position et attente estimée visibles', async ({ page }) => {
  await page.route('**/v1/appointments/appt-001/queue', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        position: 3,
        estimated_wait_minutes: 12,
      }),
    }),
  );

  await page.goto('/patient/rdv/appt-001/salle-attente');

  await expect(page.locator('#queue-card')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#queue-loading')).toBeHidden();
  await expect(page.locator('#queue-position')).toContainText('3');
  await expect(page.locator('#queue-wait')).toContainText('12 min');
});

// ─── error path — API 404 ─────────────────────────────────────────────────

test('error path — API 404 : message d\'erreur affiché, carte masquée', async ({ page }) => {
  await page.route('**/v1/appointments/appt-404/queue', (route) =>
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found' }),
    }),
  );

  await page.goto('/patient/rdv/appt-404/salle-attente');

  await expect(page.locator('#queue-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#queue-card')).toBeHidden();
});
