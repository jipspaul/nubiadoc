import { test, expect } from '@playwright/test';

const PAGE_URL = '/clinical/patients/p-test-1/medical-record';

test('la page GET/PATCH medical-record affiche les sections et le formulaire', async ({ page }) => {
  await page.goto(PAGE_URL);
  await expect(page.locator('#access-token')).toBeVisible();
  await expect(page.locator('#patient-id')).toBeVisible();
  await expect(page.locator('#h-get')).toBeVisible();
  await expect(page.locator('#h-patch')).toBeVisible();
  await expect(page.locator('#result-get')).toBeVisible();
  await expect(page.locator('#result-patch')).toBeVisible();
  await expect(page.locator('#form-patch textarea[name="allergies"]')).toBeVisible();
  await expect(page.locator('#form-patch textarea[name="current_treatments"]')).toBeVisible();
  await expect(page.locator('#form-patch textarea[name="medical_history"]')).toBeVisible();
});

test('GET medical-record avec token secretary → 403 affiché dans result-get', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/*/medical-record', (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('secretary-token');
  await page.locator('#patient-id').fill('p-test-1');
  await page.locator('#form-get button[type="submit"]').click();
  await expect(page.locator('#result-get')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#result-get')).toContainText('forbidden');
});

test('GET medical-record praticien → 200 et formulaire PATCH pré-rempli', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/*/medical-record', (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        allergies: 'Pénicilline',
        current_treatments: 'Metformine 500 mg',
        medical_history: 'Diabète type 2',
      }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('practitioner-token');
  await page.locator('#patient-id').fill('p-test-1');
  await page.locator('#form-get button[type="submit"]').click();
  await expect(page.locator('#result-get')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#field-allergies')).toHaveValue('Pénicilline');
  await expect(page.locator('#field-current-treatments')).toHaveValue('Metformine 500 mg');
  await expect(page.locator('#field-medical-history')).toHaveValue('Diabète type 2');
});

test('PATCH medical-record praticien → 200 affiché dans result-patch', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/*/medical-record', (route) => {
    if (route.request().method() !== 'PATCH') return route.fallback();
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ allergies: 'Latex', current_treatments: '', medical_history: 'HTA' }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('practitioner-token');
  await page.locator('#patient-id').fill('p-test-1');
  await page.locator('#form-patch textarea[name="allergies"]').fill('Latex');
  await page.locator('#form-patch textarea[name="medical_history"]').fill('HTA');
  await page.locator('#form-patch button[type="submit"]').click();
  await expect(page.locator('#result-patch')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-patch')).toContainText('Latex');
});
