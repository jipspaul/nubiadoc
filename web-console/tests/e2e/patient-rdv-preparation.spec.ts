import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/rdv/[id]/preparation affiche le titre et l\'état de chargement', async ({ page }) => {
  // Block both API calls so loading stays visible
  await page.route('**/v1/appointments/**', (route) => new Promise(() => {}));
  await page.goto('/patient/rdv/appt-001/preparation');
  await expect(page.getByRole('heading', { name: /préparation/i })).toBeVisible();
  await expect(page.locator('#prep-loading')).toBeVisible();
});

// ─── happy path — préparation chargée ────────────────────────────────────

test('happy path — préparation chargée : instructions et documents visibles', async ({ page }) => {
  await page.route('**/v1/appointments/appt-001/preparation', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        instructions: 'Venir à jeun depuis la veille.',
        documents_needed: ['Carte Vitale', 'Ordonnance médecin traitant'],
      }),
    }),
  );
  await page.route('**/v1/appointments/appt-001/directions', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        address: '12 rue de la Paix, 75001 Paris',
        map_url: 'https://maps.example.com/?q=12+rue+de+la+Paix',
      }),
    }),
  );

  await page.goto('/patient/rdv/appt-001/preparation');

  await expect(page.locator('#prep-card')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#prep-loading')).toBeHidden();
  await expect(page.locator('#prep-instructions')).toContainText('Venir à jeun');
  await expect(page.locator('#docs-section')).toBeVisible();
  await expect(page.locator('#prep-docs-list')).toContainText('Carte Vitale');
  await expect(page.locator('#prep-docs-list')).toContainText('Ordonnance médecin traitant');
});

// ─── error path — API 500 ─────────────────────────────────────────────────

test('error path — API erreur : message d\'erreur affiché, carte masquée', async ({ page }) => {
  await page.route('**/v1/appointments/appt-err/preparation', (route) =>
    route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'internal_error' }),
    }),
  );
  await page.route('**/v1/appointments/appt-err/directions', (route) =>
    route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'internal_error' }),
    }),
  );

  await page.goto('/patient/rdv/appt-err/preparation');

  await expect(page.locator('#prep-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#prep-card')).toBeHidden();
});
