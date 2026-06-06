import { test, expect } from '@playwright/test';

test('le formulaire /auth/mfa-verify est visible avec les champs requis', async ({ page }) => {
  await page.goto('/auth/mfa-verify');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="totp_secret"]')).toBeVisible();
  await expect(page.locator('input[name="totp_code"]')).toBeVisible();
  await expect(page.locator('form#mfa-verify-form button[type="submit"]')).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('submit avec credentials bidon affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/auth/mfa-verify');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="totp_secret"]').fill('JBSWY3DPEHPK3PXP');
  await page.locator('input[name="totp_code"]').fill('123456');
  await page.locator('form#mfa-verify-form button[type="submit"]').click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/auth/mfa-verify');
});
