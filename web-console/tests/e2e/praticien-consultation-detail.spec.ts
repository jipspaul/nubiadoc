import { test, expect } from '@playwright/test';

const CONSULTATION_ID = '00000000-0000-0000-0000-000000000042';
const ROUTE = `/praticien/consultation/${CONSULTATION_ID}`;

test('render — /praticien/consultation/:id affiche les sections principales', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.goto(ROUTE);
  await expect(page.getByRole('heading', { name: 'Fauteuil clinique', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Détails de la consultation', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Actes réalisés', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Ajouter un acte', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Terminer la consultation', level: 2 })).toBeVisible();
});

test('render — formulaire ajout d\'acte présente les champs et le bouton', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.goto(ROUTE);
  await expect(page.getByLabel('Code acte', { exact: false })).toBeVisible();
  await expect(page.getByLabel('Libellé')).toBeVisible();
  await expect(page.getByLabel('Quantité')).toBeVisible();
  await expect(page.getByRole('button', { name: "Ajouter l'acte" })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Terminer la consultation' })).toBeVisible();
});

test('happy path — GET consultation 200 affiche les détails', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route(`**/v1/cabinet/consultations/${CONSULTATION_ID}`, (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: CONSULTATION_ID,
        status: 'in_progress',
        patient_id: 'patient-uuid-1',
        appointment_id: 'appt-uuid-1',
        started_at: '2026-06-08T09:00:00Z',
        completed_at: null,
        acts: [],
      }),
    });
  });
  await page.goto(ROUTE);
  await expect(page.locator('#c-status')).toContainText('in_progress', { timeout: 5000 });
  await expect(page.locator('#c-patient')).toContainText('patient-uuid-1');
  await expect(page.locator('#consultation-content')).not.toHaveAttribute('hidden');
});

test('error path — GET consultation 404 affiche un message d\'erreur', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route(`**/v1/cabinet/consultations/${CONSULTATION_ID}`, (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found' }),
    });
  });
  await page.goto(ROUTE);
  await expect(page.locator('#consultation-status')).toContainText('introuvable (404)', { timeout: 5000 });
});

test('happy path — POST acte 201 affiche confirmation et réinitialise le formulaire', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  // Initial load returns a valid consultation
  await page.route(`**/v1/cabinet/consultations/${CONSULTATION_ID}`, (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: CONSULTATION_ID,
        status: 'in_progress',
        patient_id: 'patient-uuid-1',
        appointment_id: 'appt-uuid-1',
        started_at: '2026-06-08T09:00:00Z',
        completed_at: null,
        acts: [],
      }),
    });
  });
  // POST /acts succeeds
  await page.route(`**/v1/cabinet/consultations/${CONSULTATION_ID}/acts`, (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'CCAM123', label: 'Extraction dentaire', quantity: 1 }),
    });
  });

  await page.goto(ROUTE);
  await page.getByLabel('Code acte', { exact: false }).fill('CCAM123');
  await page.getByLabel('Libellé').fill('Extraction dentaire');
  await page.getByRole('button', { name: "Ajouter l'acte" }).click();
  await expect(page.locator('#add-act-status')).toContainText('Acte ajouté', { timeout: 5000 });
  // Form should be reset (code field emptied)
  await expect(page.getByLabel('Code acte', { exact: false })).toHaveValue('');
});

test('error path — POST acte 403 affiche accès refusé', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route(`**/v1/cabinet/consultations/${CONSULTATION_ID}`, (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          id: CONSULTATION_ID,
          status: 'in_progress',
          patient_id: 'patient-uuid-1',
          appointment_id: 'appt-uuid-1',
          started_at: '2026-06-08T09:00:00Z',
          completed_at: null,
          acts: [],
        }),
      });
    } else {
      route.continue();
    }
  });
  await page.route(`**/v1/cabinet/consultations/${CONSULTATION_ID}/acts`, (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto(ROUTE);
  await page.getByLabel('Code acte', { exact: false }).fill('CCAM123');
  await page.getByRole('button', { name: "Ajouter l'acte" }).click();
  await expect(page.locator('#add-act-status')).toContainText('Accès refusé (403)', { timeout: 5000 });
});
