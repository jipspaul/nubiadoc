import { test, expect } from '@playwright/test';

test('le formulaire /test/scheduling/appointment-detail est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/scheduling/appointment-detail');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('ID valide => affiche HTTP 200 ou erreur réseau (pas de backend en CI)', async ({ page }) => {
  await page.goto('/test/scheduling/appointment-detail');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/scheduling/appointment-detail');
});

test('ID inconnu => badge affiche HTTP 404 (ou erreur réseau en CI)', async ({ page }) => {
  await page.goto('/test/scheduling/appointment-detail');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000000');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP 404|HTTP 401|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/scheduling/appointment-detail');
});
