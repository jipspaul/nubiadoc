import { test, expect } from '@playwright/test';

// ─── render ─────────────────────────────────────────────────────────────────

test('render — /patient/accueil affiche le titre et les trois sections', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'patient', domain: 'localhost', path: '/' },
  ]);
  // Block API so loading stays visible
  await page.route('**/v1/dashboard', (route) => new Promise(() => {}));
  await page.goto('/patient/accueil');
  await expect(page.getByRole('heading', { name: 'Accueil', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Prochain rendez-vous', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Messages non lus', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Devis en attente', level: 2 })).toBeVisible();
});

// ─── happy path — données dashboard chargées ────────────────────────────────

test('happy path — GET /v1/dashboard 200 : prochain RDV, messages et devis affichés', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'patient', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/dashboard', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        next_appointment: { id: 'appt-001', scheduled_at: '2026-07-15T10:00:00Z' },
        unread_messages: 3,
        pending_quotes: 1,
      }),
    }),
  );

  await page.goto('/patient/accueil');

  // Prochain RDV card visible
  await expect(page.locator('#next-rdv-card')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#next-rdv-empty')).toBeHidden();
  await expect(page.locator('#next-rdv-link')).toHaveAttribute('href', '/patient/rdv/appt-001');

  // Messages non lus
  await expect(page.locator('#messages-content')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#unread-count')).toContainText('3');

  // Devis en attente
  await expect(page.locator('#devis-content')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#pending-quotes')).toContainText('1');
});
