import { test, expect } from '@playwright/test';

test('render — /praticien/patients/:id affiche le titre, le fil d\'Ariane et les onglets', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/praticien/patients/p-test-1');
  await expect(page.getByRole('heading', { name: 'Dossier patient', level: 1 })).toBeVisible();
  await expect(page.getByRole('link', { name: '← Patients' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Dossier médical' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Notes' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Documents' })).toBeVisible();
});

test('happy path — POST /v1/cabinet/patients/:id/notes 201 ajoute la note et affiche le statut succès', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/patients/p-1/notes', (route) => {
    if (route.request().method() === 'POST') {
      route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({ id: 'note-1', body: 'Examen normal.', created_at: new Date().toISOString() }),
      });
    } else {
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
    }
  });
  await page.route('**/v1/cabinet/patients/p-1/medical-record', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ allergies: [], current_medications: [], history: '' }),
    });
  });
  await page.route('**/v1/cabinet/patients/p-1', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'p-1', last_name: 'Martin', first_name: 'Alice', date_of_birth: '1985-03-12' }),
    });
  });

  await page.goto('/praticien/patients/p-1');

  // Switch to the Notes tab
  await page.getByRole('button', { name: 'Notes' }).click();

  // Fill and submit the note form
  await page.getByLabel('Nouvelle note').fill('Examen normal.');
  await page.getByRole('button', { name: 'Ajouter la note' }).click();

  await expect(page.locator('#note-submit-status')).toContainText('Note ajoutée', { timeout: 5000 });
  await expect(page.locator('#notes-list')).toContainText('Examen normal.');
});

test('error path — GET /v1/cabinet/patients/:id/medical-record 403 affiche erreur dans la section médicale', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/patients/p-2/medical-record', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.route('**/v1/cabinet/patients/p-2', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'p-2', last_name: 'Dupont', first_name: 'Bob' }),
    });
  });

  await page.goto('/praticien/patients/p-2');
  await expect(page.locator('#medical-status')).toContainText('403', { timeout: 5000 });
});
