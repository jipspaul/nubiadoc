import { test, expect } from '@playwright/test';

test('render — /praticien/file affiche le titre et les deux sections', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/praticien/file');
  await expect(page.getByRole('heading', { name: "Salle d'attente", level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'File d\'attente', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Appeler le suivant', level: 2 })).toBeVisible();
  await expect(page.getByRole('button', { name: /appeler le patient suivant/i })).toBeVisible();
});

test('happy path — GET /v1/cabinet/waiting-room 200 affiche la table', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/waiting-room', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([{ id: 'wr-1', patient_id: 'patient-uuid-1', position: 1, checked_in_at: new Date().toISOString() }]),
    });
  });
  await page.goto('/praticien/file');
  await expect(page.locator('#queue-table')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#queue-tbody')).toContainText('patient-uuid-1');
});
