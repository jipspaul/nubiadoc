import { test, expect } from '@playwright/test';

test('render — /pro/verification affiche le formulaire avec les champs requis', async ({ page }) => {
  await page.goto('/pro/verification');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('select[name="id_type"]')).toBeVisible();
  await expect(page.locator('input[name="identifier"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /soumettre/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path — 202 avec status pending affiche badge "En attente"', async ({ page }) => {
  await page.route('**/v1/pro/verification', (route) => {
    route.fulfill({
      status: 202,
      contentType: 'application/json',
      body: JSON.stringify({ verification_id: 'verif-0001', status: 'pending' }),
    });
  });

  await page.goto('/pro/verification');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.locator('select[name="id_type"]').selectOption('rpps');
  await page.locator('input[name="identifier"]').fill('10003456789');
  await page.getByRole('button', { name: /soumettre/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 202', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('pending');
  await expect(page.locator('.status-pending')).toBeVisible();
  await expect(page.locator('.status-pending')).toContainText('En attente');
});

test('error path — 422 format invalide affiche HTTP 422', async ({ page }) => {
  await page.route('**/v1/pro/verification', (route) => {
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'invalid_identifier_format' }),
    });
  });

  await page.goto('/pro/verification');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.locator('select[name="id_type"]').selectOption('rpps');
  await page.locator('input[name="identifier"]').fill('INVALIDE');
  await page.getByRole('button', { name: /soumettre/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 422', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('invalid_identifier_format');
});
