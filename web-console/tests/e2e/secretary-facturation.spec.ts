import { test, expect } from '@playwright/test';

test('render — /secretary/facturation affiche le titre et la table devis', async ({ page }) => {
  // Page requires nubia_jwt cookie + role secretary/admin.
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/facturation');
  await expect(page.getByRole('heading', { name: 'Facturation', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Devis du cabinet', level: 2 })).toBeVisible();
  await expect(page.locator('#quotes-status')).toBeVisible();
  await expect(page.locator('#quotes-container')).toBeVisible();
});

test('error path — /secretary/facturation affiche HTTP 403 quand l\'API refuse', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/pro/cabinet/quotes**', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.route('**/v1/cabinet/quotes**', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.goto('/secretary/facturation');
  // Client-side fetch fires on load; expect 403 surfaced in the status area.
  await expect(page.locator('#quotes-status')).toContainText('403', { timeout: 5000 });
});
