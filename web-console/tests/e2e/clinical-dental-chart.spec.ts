import { test, expect } from '@playwright/test';

const PAGE_URL = '/clinical/patients/p-test-1/dental-chart';

test('la page GET/PUT dental-chart affiche la grille FDI et les formulaires', async ({ page }) => {
  await page.goto(PAGE_URL);
  await expect(page.locator('#access-token')).toBeVisible();
  await expect(page.locator('#patient-id')).toBeVisible();
  await expect(page.locator('#h-get')).toBeVisible();
  await expect(page.locator('#h-put')).toBeVisible();
  await expect(page.locator('#result-get')).toBeVisible();
  await expect(page.locator('#result-put')).toBeVisible();
  // FDI grid: spot-check a few teeth
  await expect(page.locator('#tooth-11')).toBeVisible();
  await expect(page.locator('#tooth-28')).toBeVisible();
  await expect(page.locator('#tooth-48')).toBeVisible();
  await expect(page.locator('#h-grid')).toBeVisible();
});

test('GET dental-chart praticien → 200 + grille peuplée', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/*/dental-chart', (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ '11': 'carie', '21': 'obturation', '36': 'absent' }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('practitioner-token');
  await page.locator('#patient-id').fill('p-test-1');
  await page.locator('#form-get button[type="submit"]').click();
  await expect(page.locator('#result-get')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#tooth-11')).toHaveValue('carie');
  await expect(page.locator('#tooth-21')).toHaveValue('obturation');
  await expect(page.locator('#tooth-36')).toHaveValue('absent');
});

test('GET dental-chart secretary → 403 affiché', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/*/dental-chart', (route) => {
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

test('PUT dental-chart praticien → 200 affiché', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/*/dental-chart', (route) => {
    if (route.request().method() !== 'PUT') return route.fallback();
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ '11': 'couronne' }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('practitioner-token');
  await page.locator('#patient-id').fill('p-test-1');
  await page.locator('#tooth-11').selectOption('couronne');
  await page.locator('#form-put button[type="submit"]').click();
  await expect(page.locator('#result-put')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-put')).toContainText('couronne');
});
