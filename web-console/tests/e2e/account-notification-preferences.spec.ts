import { test, expect } from '@playwright/test';

test('la page notification-preferences affiche les deux formulaires GET et PATCH', async ({ page }) => {
  await page.goto('/test/account/notification-preferences');
  await expect(page.locator('#get-form input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /^GET$/i })).toBeVisible();
  await expect(page.locator('#patch-form input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer patch/i })).toBeVisible();
  await expect(page.locator('input[name="email_appointment_reminder"]')).toBeVisible();
  await expect(page.locator('input[name="push_message"]')).toBeVisible();
  await expect(page.locator('input[name="sms_appointment_reminder"]')).toBeVisible();
});

test('GET avec token bidon affiche un résultat (erreur réseau ou HTTP)', async ({ page }) => {
  await page.goto('/test/account/notification-preferences');
  await page.locator('#get-form input[name="access_token"]').fill('fake-token');
  await page.getByRole('button', { name: /^GET$/i }).click();
  await expect(page.locator('#get-result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/account/notification-preferences');
});

test('PATCH avec token bidon et toggles cochés affiche un résultat (erreur réseau ou HTTP)', async ({ page }) => {
  await page.goto('/test/account/notification-preferences');
  await page.locator('#patch-form input[name="access_token"]').fill('fake-token');
  await page.locator('input[name="email_appointment_reminder"]').check();
  await page.locator('input[name="push_message"]').check();
  await page.getByRole('button', { name: /envoyer patch/i }).click();
  await expect(page.locator('#patch-result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/account/notification-preferences');
});
