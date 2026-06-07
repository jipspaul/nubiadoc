import { test, expect } from '@playwright/test';

test('render — /secretary/cabinet affiche le titre et le formulaire de réglages', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/cabinet');
  await expect(page.getByRole('heading', { name: 'Réglages du cabinet', level: 1 })).toBeVisible();
  await expect(page.locator('#settings-form')).toBeVisible();
  await expect(page.locator('#btn-save')).toBeVisible();
  await expect(page.locator('#get-status')).toBeVisible();
  await expect(page.locator('#patch-status')).toBeVisible();
});

test('happy path — charge les données cabinet et pré-remplit le formulaire', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: '00000000-0000-0000-0000-000000000001',
        name: 'Cabinet Dupont',
        address: '12 rue de la Paix, 75001 Paris',
        phone: '+33 1 23 45 67 89',
        siret: '12345678900012',
      }),
    });
  });
  await page.route('**/v1/cabinets/*/info', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        name: 'Cabinet Dupont',
        address: '12 rue de la Paix, 75001 Paris',
        phone: '+33 1 23 45 67 89',
      }),
    });
  });
  await page.goto('/secretary/cabinet');
  await expect(page.locator('#field-name')).toHaveValue('Cabinet Dupont', { timeout: 5000 });
  await expect(page.locator('#field-siret')).toHaveValue('12345678900012');
});

test('error path — affiche erreur 403 si l\'API refuse l\'accès', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.goto('/secretary/cabinet');
  await expect(page.locator('#get-status')).toContainText('403', { timeout: 5000 });
});
