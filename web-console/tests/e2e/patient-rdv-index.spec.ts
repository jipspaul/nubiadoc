import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/rdv affiche le titre et les sections loading', async ({ page }) => {
  // Block API so loading stays visible
  await page.route('**/v1/appointments**', (route) => new Promise(() => {}));
  await page.goto('/patient/rdv');
  await expect(page.getByRole('heading', { name: /mes rendez-vous/i })).toBeVisible();
  await expect(page.locator('#upcoming-loading')).toBeVisible();
  await expect(page.locator('#past-loading')).toBeVisible();
});

// ─── happy path — listes chargées ──────────────────────────────────────────

test('happy path — rendez-vous chargés : items visibles dans les deux sections', async ({ page }) => {
  await page.route('**/v1/appointments?status=upcoming', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: 'appt-001',
          status: 'confirmed',
          scheduled_at: '2026-07-10T09:00:00Z',
          provider_id: 'prov-123',
        },
      ]),
    }),
  );
  await page.route('**/v1/appointments?status=past', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: 'appt-002',
          status: 'completed',
          scheduled_at: '2026-05-01T14:00:00Z',
          provider_id: 'prov-456',
        },
      ]),
    }),
  );

  await page.goto('/patient/rdv');

  // Upcoming list visible, loading hidden
  await expect(page.locator('#upcoming-list')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#upcoming-loading')).toBeHidden();
  await expect(page.locator('#upcoming-list a[href="/patient/rdv/appt-001"]')).toBeVisible();

  // Past list visible, loading hidden
  await expect(page.locator('#past-list')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#past-loading')).toBeHidden();
  await expect(page.locator('#past-list a[href="/patient/rdv/appt-002"]')).toBeVisible();
});

// ─── error path — API 401 ──────────────────────────────────────────────────

test('error path — API 401 : messages d\'erreur affichés, listes masquées', async ({ page }) => {
  await page.route('**/v1/appointments**', (route) =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthenticated' }),
    }),
  );

  await page.goto('/patient/rdv');

  await expect(page.locator('#upcoming-loading')).toContainText(/impossible/i, { timeout: 5000 });
  await expect(page.locator('#upcoming-list')).toBeHidden();
  await expect(page.locator('#past-loading')).toContainText(/impossible/i, { timeout: 5000 });
  await expect(page.locator('#past-list')).toBeHidden();
});
