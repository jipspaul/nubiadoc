import { test, expect } from '@playwright/test';

test('la page /test/prescriptions affiche les 5 sections avec leurs formulaires', async ({ page }) => {
  await page.goto('/test/prescriptions');
  // Token partagé
  await expect(page.locator('#access-token')).toBeVisible();
  // Section GET
  await expect(page.locator('#h-list')).toBeVisible();
  await expect(page.locator('#form-list button[type="submit"]')).toBeVisible();
  // Section POST create
  await expect(page.locator('#h-create')).toBeVisible();
  await expect(page.locator('#form-create input[name="patient_id"]')).toBeVisible();
  await expect(page.locator('#form-create input[name="item_label"]')).toBeVisible();
  // Section PATCH
  await expect(page.locator('#h-patch')).toBeVisible();
  await expect(page.locator('#form-patch input[name="prescription_id"]')).toBeVisible();
  // Section sign
  await expect(page.locator('#h-sign')).toBeVisible();
  // Section send
  await expect(page.locator('#h-send')).toBeVisible();
  // Result zones
  await expect(page.locator('#result-list')).toBeVisible();
  await expect(page.locator('#result-create')).toBeVisible();
  await expect(page.locator('#result-sign')).toBeVisible();
  await expect(page.locator('#result-send')).toBeVisible();
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

  await page.goto('/test/prescriptions');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#form-list button[type="submit"]').click();
  await expect(page.locator('#result-list')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-list')).toContainText('rx-1');
});

test('POST /v1/cabinet/prescriptions → 201 création affichée dans result-create', async ({ page }) => {
  await page.route('**/v1/cabinet/prescriptions', (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'rx-new', status: 'draft' }),
    });
  });

  await page.goto('/test/prescriptions');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#form-create input[name="patient_id"]').fill('p-1');
  await page.locator('#form-create input[name="item_label"]').fill('Amoxicilline 500 mg');
  await page.locator('#form-create input[name="item_posology"]').fill('1 gélule 3x/jour');
  await page.locator('#form-create input[name="item_duration"]').fill('7 jours');
  await page.locator('#form-create input[name="item_quantity"]').fill('1');
  await page.locator('#form-create button[type="submit"]').click();
  await expect(page.locator('#result-create')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result-create')).toContainText('rx-new');
});

test('POST /sign → 200 signature confirmée dans result-sign', async ({ page }) => {
  await page.route('**/v1/cabinet/prescriptions/rx-1/sign', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'rx-1', status: 'signed', signed_at: '2026-06-06T12:00:00Z' }),
    });
  });

  await page.goto('/test/prescriptions');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#form-sign input[name="prescription_id"]').fill('rx-1');
  await page.locator('#form-sign button[type="submit"]').click();
  await expect(page.locator('#result-sign')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-sign')).toContainText('signed');
});

test('POST /send → 200 envoi confirmé dans result-send', async ({ page }) => {
  await page.route('**/v1/cabinet/prescriptions/rx-1/send', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'rx-1', status: 'sent', document_id: 'doc-42' }),
    });
  });

  await page.goto('/test/prescriptions');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#form-send input[name="prescription_id"]').fill('rx-1');
  await page.locator('#form-send button[type="submit"]').click();
  await expect(page.locator('#result-send')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-send')).toContainText('doc-42');
});
