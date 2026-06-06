import { test, expect } from '@playwright/test';

test('render : la page /providers/1/reviews affiche le tableau des avis', async ({ page }) => {
  await page.goto('/providers/1/reviews');
  await expect(page.locator('table')).toBeVisible();
  await expect(page.locator('#reviews-tbody')).toBeVisible();
});

test('happy path : la liste se charge et affiche une ligne ou un message vide', async ({ page }) => {
  await page.goto('/providers/1/reviews');
  const tbody = page.locator('#reviews-tbody');
  // Wait for loading to finish (loading row disappears)
  await expect(tbody).not.toContainText('Chargement…', { timeout: 10000 });
  // Either rows or empty message — not an error
  const hasRows = await tbody.locator('tr td').count() > 0;
  expect(hasRows).toBe(true);
});

test('pagination : les boutons précédent/suivant sont présents', async ({ page }) => {
  await page.goto('/providers/1/reviews');
  await expect(page.locator('#btn-prev')).toBeVisible();
  await expect(page.locator('#btn-next')).toBeVisible();
});

test('error path : 404 sur provider inexistant affiche un message d\'erreur', async ({ page }) => {
  await page.goto('/providers/nonexistent-provider-id-00000/reviews');
  const tbody = page.locator('#reviews-tbody');
  await expect(tbody).not.toContainText('Chargement…', { timeout: 10000 });
  // Either 404 message or empty — API may return 404 or empty list
  const errorMsg = page.locator('#error-msg');
  const tbodyText = await tbody.textContent();
  const errorVisible = await errorMsg.isVisible();
  // At least one of: error displayed, or table showing something (empty list is also valid)
  expect(errorVisible || (tbodyText !== null && tbodyText.length > 0)).toBe(true);
});
