import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/rdv/reserver affiche le titre et le formulaire', async ({ page }) => {
  // Block dependents API so the page still renders without a real backend
  await page.route('**/v1/account/dependents', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );

  await page.goto('/patient/rdv/reserver?slot_id=slot-001');

  await expect(page.getByRole('heading', { name: /réserver un rendez-vous/i })).toBeVisible();
  await expect(page.getByLabel(/motif de la consultation/i)).toBeVisible();
  await expect(page.getByRole('button', { name: /confirmer la réservation/i })).toBeVisible();
  // Le formulaire est visible ; la bannière d'erreur 409 doit être masquée
  await expect(page.locator('#slot-taken-error')).toBeHidden();
});

// ─── happy path — POST 201 → redirection vers la fiche RDV ────────────────

test('happy path — POST 201 → redirection vers /patient/rdv/<id>', async ({ page }) => {
  await page.route('**/v1/account/dependents', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 'dep-001', first_name: 'Marie', last_name: 'Dupont' },
      ]),
    }),
  );

  await page.route('**/v1/appointments', (route) => {
    if (route.request().method() === 'POST') {
      route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({ id: 'appt-new-001', status: 'confirmed' }),
      });
    } else {
      route.continue();
    }
  });

  await page.goto('/patient/rdv/reserver?slot_id=slot-001');

  await page.getByLabel(/motif de la consultation/i).fill('Détartrage annuel');
  await page.getByRole('button', { name: /confirmer la réservation/i }).click();

  // La redirection vers /patient/rdv/appt-new-001 doit avoir lieu
  await expect(page).toHaveURL(/\/patient\/rdv\/appt-new-001/, { timeout: 5000 });
});

// ─── error path — POST 409 slot_taken → bannière affichée ────────────────

test('error path — POST 409 slot_taken → bannière créneau pris, formulaire masqué', async ({ page }) => {
  await page.route('**/v1/account/dependents', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );

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

  await page.goto('/patient/rdv/reserver?slot_id=slot-taken');

  await page.getByLabel(/motif de la consultation/i).fill('Consultation urgente');
  await page.getByRole('button', { name: /confirmer la réservation/i }).click();

  await expect(page.locator('#slot-taken-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#reserver-form')).toBeHidden();
  // Le lien « Retour à la recherche » doit être présent dans la bannière
  await expect(page.getByRole('link', { name: /retour à la recherche/i })).toBeVisible();
});

// ─── validation — motif manquant → message d'erreur inline ───────────────

test('validation — motif vide → message d\'erreur affiché sans appel API', async ({ page }) => {
  await page.route('**/v1/account/dependents', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );

  let apiCalled = false;
  await page.route('**/v1/appointments', () => {
    apiCalled = true;
  });

  await page.goto('/patient/rdv/reserver?slot_id=slot-001');

  // Soumettre sans remplir le motif
  await page.getByRole('button', { name: /confirmer la réservation/i }).click();

  await expect(page.locator('#form-error')).toBeVisible({ timeout: 3000 });
  await expect(page.locator('#form-error')).toContainText(/motif est requis/i);
  expect(apiCalled).toBe(false);
});
