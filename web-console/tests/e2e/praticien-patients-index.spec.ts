import { test, expect } from '@playwright/test';

test('render — /praticien/patients affiche le titre et la section liste', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/praticien/patients');
  await expect(page.getByRole('heading', { name: 'Patients du cabinet', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Liste des patients', level: 2 })).toBeVisible();
  await expect(page.locator('#patients-status')).toBeVisible();
  await expect(page.locator('#patients-container')).toBeVisible();
});

test('happy path — GET /v1/cabinet/patients 200 affiche la table avec les patients', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/patients', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 'p-1', last_name: 'Martin', first_name: 'Alice', date_of_birth: '1985-03-12' },
        { id: 'p-2', last_name: 'Dupont', first_name: 'Bob', date_of_birth: '1972-07-04' },
      ]),
    });
  });
  await page.goto('/praticien/patients');
  await expect(page.locator('#patients-table')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#patients-tbody')).toContainText('Martin');
  await expect(page.locator('#patients-tbody')).toContainText('Alice');
  await expect(page.locator('#patients-tbody')).toContainText('Dupont');
});

test('error path — GET /v1/cabinet/patients 403 affiche le message d\'erreur', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/patients', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.goto('/praticien/patients');
  await expect(page.locator('#patients-status')).toContainText('403', { timeout: 5000 });
});
