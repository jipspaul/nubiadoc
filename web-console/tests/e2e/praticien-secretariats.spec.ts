import { test, expect } from '@playwright/test';

test('render — /praticien/secretariats affiche le titre et les trois sections', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/praticien/secretariats');
  await expect(page.getByRole('heading', { name: 'Mes secrétariats', level: 1 })).toBeVisible();
  await expect(page.getByRole('list', { name: 'Liste des secrétariats' })).toBeVisible();
  await expect(page.getByRole('list', { name: 'Secrétariats assignés au praticien connecté' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Assigner' })).toBeVisible();
});

test('happy path — GET /v1/cabinet/secretariats 200 affiche les secrétariats de l\'établissement', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/secretariats', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 'aaaa0000-0000-0000-0000-000000000001', name: 'Secrétariat Nord' },
        { id: 'aaaa0000-0000-0000-0000-000000000002', name: 'Secrétariat Sud' },
      ]),
    });
  });
  await page.goto('/praticien/secretariats');
  const allList = page.getByRole('list', { name: 'Liste des secrétariats' });
  await expect(allList).toContainText('Secrétariat Nord', { timeout: 5000 });
  await expect(allList).toContainText('Secrétariat Sud');
});

test('error path — GET /v1/cabinet/secretariats 403 affiche une erreur dans la section liste', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/secretariats', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.goto('/praticien/secretariats');
  await expect(page.locator('#all-status')).toContainText('403', { timeout: 5000 });
});

test('happy path — PUT /v1/cabinet/providers/:id/secretariats 200 met à jour l\'assignation', async ({ page }) => {
  const providerId = 'bbbb0000-0000-0000-0000-000000000001';
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route(`**/v1/cabinet/providers/${providerId}/secretariats`, (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([{ id: 'aaaa0000-0000-0000-0000-000000000001', name: 'Secrétariat Nord' }]),
    });
  });
  await page.route('**/v1/cabinet/secretariats', (route) => {
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/me', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ id: providerId }),
    });
  });

  await page.goto('/praticien/secretariats');
  await page.getByLabel(/Provider ID/).fill(providerId);
  await page.getByLabel(/IDs des secrétariats/).fill('aaaa0000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: 'Assigner' }).click();
  await expect(page.locator('#result-assign')).toContainText('HTTP 200', { timeout: 5000 });
});

test('error path — PUT /v1/cabinet/providers/:id/secretariats 422 affiche une erreur dans le résultat', async ({ page }) => {
  const providerId = 'bbbb0000-0000-0000-0000-000000000002';
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route(`**/v1/cabinet/providers/${providerId}/secretariats`, (route) => {
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'invalid_secretariat_ids' }),
    });
  });
  await page.route('**/v1/cabinet/secretariats', (route) => {
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/me', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ id: providerId }),
    });
  });

  await page.goto('/praticien/secretariats');
  await page.getByLabel(/Provider ID/).fill(providerId);
  await page.getByLabel(/IDs des secrétariats/).fill('not-a-valid-uuid');
  await page.getByRole('button', { name: 'Assigner' }).click();
  await expect(page.locator('#result-assign')).toContainText('HTTP 422', { timeout: 5000 });
});
