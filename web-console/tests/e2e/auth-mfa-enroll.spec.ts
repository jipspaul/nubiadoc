import { test, expect } from '@playwright/test';

test('le formulaire /auth/mfa-enroll est visible avec les champs requis', async ({ page }) => {
  await page.goto('/auth/mfa-enroll');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('form#mfa-enroll-form button[type="submit"]')).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('submit avec token bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/auth/mfa-enroll');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('form#mfa-enroll-form button[type="submit"]').click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/auth/mfa-enroll');
});
