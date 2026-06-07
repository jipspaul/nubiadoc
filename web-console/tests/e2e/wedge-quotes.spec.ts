import { test, expect } from '@playwright/test';

test('render: le formulaire /test/wedge/quotes est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/wedge/quotes');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="status"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /^GET$/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path: 200 => liste des devis avec statut, montant et date affichés', async ({ page }) => {
  await page.route('**/v1/quotes', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: '00000000-0000-0000-0000-000000000001',
          status: 'pending',
          amount_cents: 20600,
          created_at: '2026-06-01T10:00:00Z',
        },
        {
          id: '00000000-0000-0000-0000-000000000002',
          status: 'signed',
          amount_cents: 54000,
          created_at: '2026-05-15T08:30:00Z',
        },
      ]),
    });
  });

  await page.goto('/test/wedge/quotes');
  await page.locator('input[name="access_token"]').fill('valid-patient-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#quotes-list')).toBeVisible();
  await expect(page.locator('#quotes-tbody')).toContainText('pending');
  await expect(page.locator('#quotes-tbody')).toContainText('206.00');
  await expect(page.locator('#quotes-tbody')).toContainText('signed');
});

test('error path: 401 => token invalide affiché dans le résultat', async ({ page }) => {
  await page.route('**/v1/quotes', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthenticated' }),
    });
  });

  await page.goto('/test/wedge/quotes');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.getByRole('button', { name: /^GET$/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthenticated');
  await expect(page.locator('#quotes-list')).not.toBeVisible();
});
