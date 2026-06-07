import { test, expect } from '@playwright/test';

test('render: formulaire /test/documents/detail est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/documents/detail');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="document_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /charger/i })).toBeVisible();
});

test('error path: UUID inexistant affiche un message d\'erreur 404', async ({ page }) => {
  await page.goto('/test/documents/detail');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="document_id"]').fill('00000000-0000-0000-0000-000000000000');
  await page.getByRole('button', { name: /charger/i }).click();
  await expect(page.locator('#error-box')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/documents/detail');
});
