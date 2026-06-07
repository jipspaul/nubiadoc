import { test, expect } from '@playwright/test';

// --- /clinical/patients/[id] ---

test('render — /clinical/patients/:id affiche le formulaire fiche', async ({ page }) => {
  await page.goto('/clinical/patients/p-test-1');
  await expect(page.locator('#fiche-form input[name="access_token"]')).toBeVisible();
  await expect(page.locator('#fiche-form input[name="patient_id"]')).toBeVisible();
  await expect(page.locator('#fiche-result')).toBeVisible();
});

test('happy path — GET 200 rôle practitioner affiche les sections cliniques', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/p-1', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'p-1',
        display_name: 'Alice Martin',
        administrative: { birth_date: '1985-03-12', phone: '0600000001' },
        clinical: { allergies: ['pénicilline'], antecedents: [] },
      }),
    });
  });

  await page.goto('/clinical/patients/p-1');
  await page.locator('#fiche-form input[name="access_token"]').fill('practitioner-token');
  await page.locator('#fiche-form input[name="patient_id"]').fill('p-1');
  await page.locator('#fiche-form button[type="submit"]').click();

  await expect(page.locator('#fiche-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#fiche-result')).toContainText('Alice Martin');
  await expect(page.locator('#clinical-section')).toBeVisible();
  await expect(page.locator('#masked-section')).not.toBeVisible();
});

test('secretary — GET 200 sans section clinique affiche le bandeau masqué (R.4127-72)', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/p-2', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'p-2',
        display_name: 'Bob Dupont',
        administrative: { birth_date: '1972-07-04' },
        // no 'clinical' key — secretary view
      }),
    });
  });

  await page.goto('/clinical/patients/p-2');
  await page.locator('#fiche-form input[name="access_token"]').fill('secretary-token');
  await page.locator('#fiche-form input[name="patient_id"]').fill('p-2');
  await page.locator('#fiche-form button[type="submit"]').click();

  await expect(page.locator('#fiche-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#masked-section')).toBeVisible();
  await expect(page.locator('#clinical-section')).not.toBeVisible();
});

// --- /clinical/patients/[id]/documents ---

test('render — /clinical/patients/:id/documents affiche les formulaires liste et upload', async ({ page }) => {
  await page.goto('/clinical/patients/p-test-1/documents');
  await expect(page.locator('#list-form input[name="access_token"]')).toBeVisible();
  await expect(page.locator('#list-form input[name="patient_id"]')).toBeVisible();
  await expect(page.locator('#upload-form select[name="category"]')).toBeVisible();
  await expect(page.locator('#upload-form input[name="file"]')).toBeVisible();
  await expect(page.locator('#list-result')).toBeVisible();
  await expect(page.locator('#upload-result')).toBeVisible();
});

test('happy path — POST upload 201 affiche document_id', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/p-3/documents', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ document_id: 'doc-abc123', filename: 'radio.pdf' }),
    });
  });

  await page.goto('/clinical/patients/p-3/documents');
  await page.locator('#upload-form input[name="access_token"]').fill('pro-token');
  await page.locator('#upload-form input[name="patient_id"]').fill('p-3');
  await page.locator('#upload-form select[name="category"]').selectOption('radio');

  // Provide a dummy file via input
  await page.locator('#upload-form input[name="file"]').setInputFiles({
    name: 'radio.pdf',
    mimeType: 'application/pdf',
    buffer: Buffer.from('fake-pdf'),
  });

  await page.locator('#upload-form button[type="submit"]').click();
  await expect(page.locator('#upload-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#upload-result')).toContainText('doc-abc123');
});
