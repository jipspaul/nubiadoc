import { test, expect } from '@playwright/test';

test('render: /test/cabinet/prescriptions/new affiche le formulaire de création et la section liste', async ({ page }) => {
  await page.goto('/test/cabinet/prescriptions/new');
  await expect(page.locator('#h-create')).toBeVisible();
  await expect(page.locator('#access-token')).toBeVisible();
  await expect(page.locator('#form-create input[name="patient_id"]')).toBeVisible();
  await expect(page.locator('#form-create input[name="item_label"]')).toBeVisible();
  await expect(page.locator('#btn-create')).toBeVisible();
  await expect(page.locator('#result-create')).toBeVisible();
  await expect(page.locator('#h-list')).toBeVisible();
  await expect(page.locator('#btn-list')).toBeVisible();
  await expect(page.locator('#result-list')).toBeVisible();
});

test('happy path: POST /v1/cabinet/prescriptions → 201 affiché dans result-create', async ({ page }) => {
  await page.route('**/v1/cabinet/prescriptions', (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'rx-new', status: 'draft' }),
    });
  });

  await page.goto('/test/cabinet/prescriptions/new');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#form-create input[name="patient_id"]').fill('p-1');
  await page.locator('#form-create input[name="item_label"]').fill('Amoxicilline 500 mg');
  await page.locator('#form-create input[name="item_posology"]').fill('1 gélule 3x/jour');
  await page.locator('#form-create input[name="item_duration"]').fill('7 jours');
  await page.locator('#form-create input[name="item_quantity"]').fill('1');
  await page.locator('#btn-create').click();
  await expect(page.locator('#result-create')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result-create')).toContainText('rx-new');
});

test('error path: POST /v1/cabinet/prescriptions → 403 forbidden affiché dans result-create', async ({ page }) => {
  await page.route('**/v1/cabinet/prescriptions', (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden', title: 'Accès refusé' }),
    });
  });

  await page.goto('/test/cabinet/prescriptions/new');
  await page.locator('#access-token').fill('secretary-token');
  await page.locator('#form-create input[name="patient_id"]').fill('p-1');
  await page.locator('#form-create input[name="item_label"]').fill('Ibuprofène 400 mg');
  await page.locator('#form-create input[name="item_posology"]').fill('1 cp 3x/jour');
  await page.locator('#form-create input[name="item_duration"]').fill('5 jours');
  await page.locator('#form-create input[name="item_quantity"]').fill('1');
  await page.locator('#btn-create').click();
  await expect(page.locator('#result-create')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#result-create')).toContainText('forbidden');
});

test('GET /v1/cabinet/prescriptions → liste affichée dans result-list', async ({ page }) => {
  await page.route('**/v1/cabinet/prescriptions**', (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 'rx-1', patient_id: 'p-1', status: 'draft', created_at: '2026-06-01T10:00:00Z' },
        { id: 'rx-2', patient_id: 'p-2', status: 'signed', created_at: '2026-06-02T09:00:00Z' },
      ]),
    });
  });

  await page.goto('/test/cabinet/prescriptions/new');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#btn-list').click();
  await expect(page.locator('#result-list')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-list')).toContainText('rx-1');
});
