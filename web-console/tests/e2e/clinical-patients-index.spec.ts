import { test, expect } from '@playwright/test';

test('render — /clinical/patients/index affiche les formulaires liste et rattachement', async ({ page }) => {
  await page.goto('/clinical/patients');
  await expect(page.locator('#patients-list-form input[name="access_token"]')).toBeVisible();
  await expect(page.locator('#patients-list-form select[name="filter"]')).toBeVisible();
  await expect(page.locator('#patients-attach-form input[name="patient_account_id"]')).toBeVisible();
  await expect(page.locator('#list-result')).toBeVisible();
  await expect(page.locator('#attach-result')).toBeVisible();
});

test('happy path — GET 200 liste les dossiers patients', async ({ page }) => {
  await page.route('**/v1/cabinet/patients**', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: [
          { id: 'p-1', display_name: 'Alice Martin' },
          { id: 'p-2', display_name: 'Bob Dupont' },
        ],
        page: { next_cursor: null, limit: 20 },
      }),
    });
  });

  await page.goto('/clinical/patients');
  await page.locator('#patients-list-form input[name="access_token"]').fill('valid-pro-token');
  await page.locator('#patients-list-form button[type="submit"]').click();
  await expect(page.locator('#list-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#list-result')).toContainText('Alice Martin');
});

test('happy path — POST 201 rattache un patient au cabinet', async ({ page }) => {
  await page.route('**/v1/cabinet/patients', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'p-3', patient_account_id: '00000000-0000-0000-0000-000000000003' }),
    });
  });

  await page.goto('/clinical/patients');
  await page.locator('#patients-attach-form input[name="access_token"]').fill('valid-pro-token');
  await page.locator('#patients-attach-form input[name="patient_account_id"]').fill('00000000-0000-0000-0000-000000000003');
  await page.locator('#patients-attach-form button[type="submit"]').click();
  await expect(page.locator('#attach-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#attach-result')).toContainText('p-3');
});

test('error path — GET 401 token invalide affiché dans le résultat', async ({ page }) => {
  await page.route('**/v1/cabinet/patients**', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthenticated' }),
    });
  });

  await page.goto('/clinical/patients');
  await page.locator('#patients-list-form input[name="access_token"]').fill('expired-token');
  await page.locator('#patients-list-form button[type="submit"]').click();
  await expect(page.locator('#list-result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#list-result')).toContainText('unauthenticated');
});

test('error path — POST 403 accès refusé affiché dans le résultat', async ({ page }) => {
  await page.route('**/v1/cabinet/patients', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/clinical/patients');
  await page.locator('#patients-attach-form input[name="access_token"]').fill('patient-token');
  await page.locator('#patients-attach-form input[name="patient_account_id"]').fill('00000000-0000-0000-0000-000000000004');
  await page.locator('#patients-attach-form button[type="submit"]').click();
  await expect(page.locator('#attach-result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#attach-result')).toContainText('forbidden');
});
