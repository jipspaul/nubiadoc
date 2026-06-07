import { test, expect } from '@playwright/test';

test('render — /cabinet/provider-listing affiche le formulaire toggle', async ({ page }) => {
  await page.goto('/cabinet/provider-listing');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="listed"][value="true"]')).toBeVisible();
  await expect(page.locator('input[name="listed"][value="false"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /put/i })).toBeVisible();
  await expect(page.locator('#listing-result')).toBeVisible();
});

test('happy path — PUT 200 listed:true affiche is_listed:true', async ({ page }) => {
  await page.route('**/v1/cabinet/provider/listing', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ is_listed: true }),
    });
  });

  await page.goto('/cabinet/provider-listing');
  await page.locator('input[name="access_token"]').fill('admin-token');
  await page.locator('input[name="listed"][value="true"]').check();
  await page.getByRole('button', { name: /put/i }).click();
  await expect(page.locator('#listing-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#listing-result')).toContainText('is_listed');
  await expect(page.locator('#listing-result')).toContainText('true');
});

test('error path — PUT 409 provider_not_verified affiche le code erreur et le lien vérification', async ({ page }) => {
  await page.route('**/v1/cabinet/provider/listing', (route) => {
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'provider_not_verified' }),
    });
  });

  await page.goto('/cabinet/provider-listing');
  await page.locator('input[name="access_token"]').fill('unverified-token');
  await page.locator('input[name="listed"][value="true"]').check();
  await page.getByRole('button', { name: /put/i }).click();
  await expect(page.locator('#listing-result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#listing-result')).toContainText('provider_not_verified');
  await expect(page.locator('a[href="/pro/verification"]')).toBeVisible();
});

test('happy path — PUT 200 listed:false affiche is_listed:false', async ({ page }) => {
  await page.route('**/v1/cabinet/provider/listing', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ is_listed: false }),
    });
  });

  await page.goto('/cabinet/provider-listing');
  await page.locator('input[name="access_token"]').fill('admin-token');
  await page.locator('input[name="listed"][value="false"]').check();
  await page.getByRole('button', { name: /put/i }).click();
  await expect(page.locator('#listing-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#listing-result')).toContainText('is_listed');
  await expect(page.locator('#listing-result')).toContainText('false');
});
