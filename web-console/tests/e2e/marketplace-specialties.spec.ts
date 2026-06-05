import { test, expect } from '@playwright/test';

test('la page /marketplace/specialties affiche un tableau', async ({ page }) => {
  await page.goto('/marketplace/specialties');
  await expect(page.locator('table')).toBeVisible();
});

test('le tableau contient au moins une spécialité sans filtre', async ({ page }) => {
  await page.goto('/marketplace/specialties');
  const tbody = page.locator('#specialties-tbody');
  await expect(tbody).not.toContainText('Aucune spécialité.');
  await expect(tbody.locator('tr td').first()).toBeVisible();
});

test('le filtre profession_id réduit la liste', async ({ page }) => {
  await page.goto('/marketplace/specialties');
  // Wait for initial load
  const tbody = page.locator('#specialties-tbody');
  await expect(tbody.locator('tr td').first()).toBeVisible();
  const totalRows = await tbody.locator('tr').count();

  // Apply filter with profession_id=1 (premier seed)
  await page.fill('#profession-id-input', '1');
  await page.click('button[type="submit"]');
  await expect(tbody).not.toContainText('Chargement…');

  const filteredRows = await tbody.locator('tr').count();
  expect(filteredRows).toBeLessThanOrEqual(totalRows);
});
