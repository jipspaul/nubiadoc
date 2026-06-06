import { test, expect } from '@playwright/test';

test('le formulaire /test/clinical/patients est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/clinical/patients');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="q"]')).toBeVisible();
  await expect(page.locator('select[name="filter"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('200 — liste de patients affichée dans le résultat', async ({ page }) => {
  await page.route('**/v1/cabinet/patients**', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ patients: [{ id: 'p-1', display_name: 'Alice Martin' }, { id: 'p-2', display_name: 'Bob Dupont' }] }),
    });
  });

  await page.goto('/test/clinical/patients');
  await page.locator('input[name="access_token"]').fill('valid-pro-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('Alice Martin');
});

test('403 — accès refusé (rôle patient) affiché dans le résultat', async ({ page }) => {
  await page.route('**/v1/cabinet/patients**', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/test/clinical/patients');
  await page.locator('input[name="access_token"]').fill('patient-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('forbidden');
});

test('401 — token invalide affiche une erreur 401', async ({ page }) => {
  await page.route('**/v1/cabinet/patients**', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/test/clinical/patients');
  await page.locator('input[name="access_token"]').fill('invalid-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});
