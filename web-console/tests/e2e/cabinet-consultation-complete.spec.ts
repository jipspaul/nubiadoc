import { test, expect } from '@playwright/test';

test('render: /test/cabinet/consultations/consult-1/complete affiche le formulaire', async ({ page }) => {
  await page.goto('/test/cabinet/consultations/consult-1/complete');
  await expect(page.locator('#h-complete')).toBeVisible();
  await expect(page.locator('#access-token')).toBeVisible();
  await expect(page.locator('#consultation-id')).toBeVisible();
  await expect(page.locator('#btn-complete')).toBeVisible();
  await expect(page.locator('#result-complete')).toBeVisible();
});

test('happy path: POST /complete → 200 affiche invoice_id et next_step', async ({ page }) => {
  await page.route('**/v1/cabinet/consultations/consult-1/complete', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        invoice_id: 'inv-abc-123',
        next_step: 'payment',
      }),
    });
  });

  await page.goto('/test/cabinet/consultations/consult-1/complete');
  await page.locator('#access-token').fill('valid-practitioner-token');
  await page.locator('#consultation-id').fill('consult-1');
  await page.locator('#btn-complete').click();
  await expect(page.locator('#result-complete')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result-complete')).toContainText('inv-abc-123');
  await expect(page.locator('#result-complete')).toContainText('next_step');
});
