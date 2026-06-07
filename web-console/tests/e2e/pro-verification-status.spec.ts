import { test, expect } from '@playwright/test';

test('render — /pro/verification-status affiche le formulaire et le champ access_token', async ({ page }) => {
  await page.goto('/pro/verification-status');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#status-result')).toBeVisible();
});

test('status pending — GET retourne pending affiche badge "En attente" jaune', async ({ page }) => {
  await page.route('**/v1/pro/verification', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ status: 'pending', verification_id: 'verif-0001' }),
    });
  });

  await page.goto('/pro/verification-status');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.getByRole('button', { name: /get/i }).click();

  await expect(page.locator('#status-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#status-result')).toContainText('pending');
  await expect(page.locator('.status-pending')).toBeVisible();
  await expect(page.locator('.status-pending')).toContainText('En attente');
});

test('status verified — GET retourne verified affiche badge "Vérifié" vert', async ({ page }) => {
  await page.route('**/v1/pro/verification', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ status: 'verified', verification_id: 'verif-0002' }),
    });
  });

  await page.goto('/pro/verification-status');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.getByRole('button', { name: /get/i }).click();

  await expect(page.locator('#status-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#status-result')).toContainText('verified');
  await expect(page.locator('.status-verified')).toBeVisible();
  await expect(page.locator('.status-verified')).toContainText('Vérifié');
});

test('status rejected — GET retourne rejected affiche badge "Rejeté" rouge et message aide', async ({ page }) => {
  await page.route('**/v1/pro/verification', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ status: 'rejected', verification_id: 'verif-0003' }),
    });
  });

  await page.goto('/pro/verification-status');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.getByRole('button', { name: /get/i }).click();

  await expect(page.locator('#status-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#status-result')).toContainText('rejected');
  await expect(page.locator('.status-rejected')).toBeVisible();
  await expect(page.locator('.status-rejected')).toContainText('Rejeté');
  await expect(page.locator('#help-rejected')).toBeVisible();
  await expect(page.locator('a[href="/pro/verification"]')).toBeVisible();
});
