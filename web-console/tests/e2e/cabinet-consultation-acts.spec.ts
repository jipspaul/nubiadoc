import { test, expect } from '@playwright/test';

const PAGE_URL = '/test/cabinet/consultations/c-test-1/acts';

test('render — la page affiche les sections GET et POST', async ({ page }) => {
  await page.goto(PAGE_URL);
  await expect(page.locator('#access-token')).toBeVisible();
  await expect(page.locator('#consultation-id')).toBeVisible();
  await expect(page.locator('#h-get')).toBeVisible();
  await expect(page.locator('#h-post')).toBeVisible();
  await expect(page.locator('#result-get')).toBeVisible();
  await expect(page.locator('#result-post')).toBeVisible();
  await expect(page.locator('#form-post input[name="ccam_code"]')).toBeVisible();
  await expect(page.locator('#form-post input[name="label"]')).toBeVisible();
});

test('POST /v1/cabinet/consultations/{id}/acts → 201 acte créé affiché dans result-post', async ({ page }) => {
  await page.route('**/v1/cabinet/consultations/*/acts', (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'act-1', ccam_code: 'HBFD001', label: 'Détartrage supragingival', tooth: '21', amount_cents: 2500, included: false }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#consultation-id').fill('c-test-1');
  await page.locator('#form-post input[name="ccam_code"]').fill('HBFD001');
  await page.locator('#form-post input[name="label"]').fill('Détartrage supragingival');
  await page.locator('#form-post input[name="tooth"]').fill('21');
  await page.locator('#form-post button[type="submit"]').click();
  await expect(page.locator('#result-post')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result-post')).toContainText('act-1');
  await expect(page.locator('#result-post')).toContainText('HBFD001');
});

test('GET /v1/cabinet/consultations/{id}/acts → 200 liste affichée dans result-get', async ({ page }) => {
  await page.route('**/v1/cabinet/consultations/*/acts', (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: [
          { id: 'act-1', ccam_code: 'HBFD001', label: 'Détartrage supragingival', tooth: '21', amount_cents: 2500, included: false },
          { id: 'act-2', ccam_code: 'HBGD001', label: 'Extraction dentaire', tooth: '36', amount_cents: 5000, included: true },
        ],
      }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#consultation-id').fill('c-test-1');
  await page.locator('#form-get button[type="submit"]').click();
  await expect(page.locator('#result-get')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-get')).toContainText('HBFD001');
  await expect(page.locator('#result-get')).toContainText('Extraction dentaire');
});
