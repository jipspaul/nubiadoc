import { test, expect } from '@playwright/test';

test('la page /marketplace/acts affiche un tableau', async ({ page }) => {
  await page.goto('/marketplace/acts');
  await expect(page.locator('table')).toBeVisible();
});

test('le tableau contient au moins un acte sans filtre', async ({ page }) => {
  await page.goto('/marketplace/acts');
  const tbody = page.locator('#acts-tbody');
  await expect(tbody).not.toContainText('Aucun acte.');
  await expect(tbody.locator('tr td').first()).toBeVisible();
});

test('le filtre specialty_id réduit ou conserve la liste', async ({ page }) => {
  await page.goto('/marketplace/acts');
  const tbody = page.locator('#acts-tbody');
  await expect(tbody.locator('tr td').first()).toBeVisible();
  const totalRows = await tbody.locator('tr').count();

  await page.fill('#specialty-id-input', '1');
  await page.click('button[type="submit"]');
  await expect(tbody).not.toContainText('Chargement…');

  const filteredRows = await tbody.locator('tr').count();
  expect(filteredRows).toBeLessThanOrEqual(totalRows);
});
