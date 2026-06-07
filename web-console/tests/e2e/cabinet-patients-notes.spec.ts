import { test, expect } from '@playwright/test';

const PAGE_URL = '/test/cabinet/patients/p-test-1/notes';

test('la page /test/cabinet/patients/{id}/notes affiche les sections GET et POST', async ({ page }) => {
  await page.goto(PAGE_URL);
  await expect(page.locator('#access-token')).toBeVisible();
  await expect(page.locator('#patient-id')).toBeVisible();
  await expect(page.locator('#h-get')).toBeVisible();
  await expect(page.locator('#h-post')).toBeVisible();
  await expect(page.locator('#result-get')).toBeVisible();
  await expect(page.locator('#result-post')).toBeVisible();
  await expect(page.locator('#form-post select[name="note_kind"]')).toBeVisible();
  await expect(page.locator('#form-post textarea[name="text"]')).toBeVisible();
});

test('POST /v1/cabinet/patients/{id}/notes → 201 note créée affichée dans result-post', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/*/notes', (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'note-1', note_kind: 'observation', text: 'RAS', created_at: '2026-06-07T10:00:00Z' }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#patient-id').fill('p-test-1');
  await page.locator('#form-post select[name="note_kind"]').selectOption('observation');
  await page.locator('#form-post textarea[name="text"]').fill('RAS');
  await page.locator('#form-post button[type="submit"]').click();
  await expect(page.locator('#result-post')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result-post')).toContainText('note-1');
});

test('GET /v1/cabinet/patients/{id}/notes → 200 timeline affichée dans result-get', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/*/notes', (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: [
          { id: 'note-1', note_kind: 'observation', text: 'RAS', created_at: '2026-06-07T10:00:00Z' },
          { id: 'note-2', note_kind: 'act', text: 'Détartrage', tooth: '21', created_at: '2026-06-06T09:00:00Z' },
        ],
        page: { next_cursor: null, limit: 20 },
      }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#patient-id').fill('p-test-1');
  await page.locator('#form-get button[type="submit"]').click();
  await expect(page.locator('#result-get')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-get')).toContainText('note-1');
  await expect(page.locator('#result-get')).toContainText('Détartrage');
});

test('POST 403 — rôle non-praticien → erreur affichée dans result-post', async ({ page }) => {
  await page.route('**/v1/cabinet/patients/*/notes', (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto(PAGE_URL);
  await page.locator('#access-token').fill('secretary-token');
  await page.locator('#patient-id').fill('p-test-1');
  await page.locator('#form-post textarea[name="text"]').fill('tentative secrétaire');
  await page.locator('#form-post button[type="submit"]').click();
  await expect(page.locator('#result-post')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#result-post')).toContainText('forbidden');
});
