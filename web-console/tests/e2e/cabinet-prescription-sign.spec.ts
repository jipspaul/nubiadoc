import { test, expect } from '@playwright/test';

test('render: /test/cabinet/prescriptions/rx-1/sign affiche le formulaire de signature', async ({ page }) => {
  await page.goto('/test/cabinet/prescriptions/rx-1/sign');
  await expect(page.locator('#h-sign')).toBeVisible();
  await expect(page.locator('#access-token')).toBeVisible();
  await expect(page.locator('#prescription-id')).toBeVisible();
  await expect(page.locator('#btn-sign')).toBeVisible();
  await expect(page.locator('#result-sign')).toBeVisible();
});

test('happy path: POST /sign → 200 affiche signed_at et document_id', async ({ page }) => {
  await page.route('**/v1/cabinet/prescriptions/rx-1/sign', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'rx-1',
        status: 'signed',
        signed_at: '2026-06-07T12:00:00Z',
        document_id: 'doc-99',
      }),
    });
  });

  await page.goto('/test/cabinet/prescriptions/rx-1/sign');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#prescription-id').fill('rx-1');
  await page.locator('#btn-sign').click();
  await expect(page.locator('#result-sign')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-sign')).toContainText('signed_at');
  await expect(page.locator('#result-sign')).toContainText('doc-99');
});
