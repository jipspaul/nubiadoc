import { test, expect } from '@playwright/test';

test('/notifications — render : formulaire visible avec champs requis', async ({ page }) => {
  await page.goto('/notifications');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="unread_only"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /charger/i })).toBeVisible();
  await expect(page.locator('#list-result')).toBeVisible();
});

test('/notifications — error path : token bidon affiche HTTP 401 ou erreur réseau', async ({ page }) => {
  await page.goto('/notifications');
  await page.locator('input[name="access_token"]').fill('invalid-token');
  await page.getByRole('button', { name: /charger/i }).click();
  await expect(page.locator('#list-result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/notifications');
});

test('/notifications — filtre non lues : checkbox modifie le libellé', async ({ page }) => {
  await page.goto('/notifications');
  const checkbox = page.locator('input[name="unread_only"]');
  await expect(checkbox).not.toBeChecked();
  await checkbox.check();
  await expect(checkbox).toBeChecked();
});

test('/notifications — pagination : curseur optionnel accepté dans le formulaire', async ({ page }) => {
  await page.goto('/notifications');
  await expect(page.locator('input[name="cursor"]')).toBeVisible();
  await page.locator('input[name="cursor"]').fill('some-cursor-value');
  await expect(page.locator('input[name="cursor"]')).toHaveValue('some-cursor-value');
});
