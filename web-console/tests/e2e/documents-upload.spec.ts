import { test, expect } from '@playwright/test';

test('le formulaire /documents/upload est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/documents/upload');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('select[name="category"]')).toBeVisible();
  await expect(page.locator('input[name="file"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /uploader/i })).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/documents/upload');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('select[name="category"]').selectOption('radio');
  await page.locator('input[name="file"]').setInputFiles({
    name: 'test.pdf',
    mimeType: 'application/pdf',
    buffer: Buffer.from('%PDF-1.4 fake'),
  });
  await page.getByRole('button', { name: /uploader/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/documents/upload');
});
