import { test, expect } from '@playwright/test';

test('le formulaire /devices/register est visible avec les champs requis', async ({ page }) => {
  await page.goto('/devices/register');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="fcm_token"]')).toBeVisible();
  await expect(page.locator('select[name="platform"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /enregistrer le device/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path : POST /v1/devices 201 => id affiché', async ({ page }) => {
  await page.route('**/v1/devices', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ id: '00000000-0000-0000-0000-000000000001' }),
    });
  });

  await page.goto('/devices/register');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="fcm_token"]').fill('fake-fcm-token');
  await page.locator('select[name="platform"]').selectOption('android');
  await page.getByRole('button', { name: /enregistrer le device/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#device-id')).toContainText('00000000-0000-0000-0000-000000000001');
});

test('401 sans JWT => erreur affichée', async ({ page }) => {
  await page.route('**/v1/devices', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized', title: 'Non authentifié' }),
    });
  });

  await page.goto('/devices/register');
  await page.locator('input[name="access_token"]').fill('');
  await page.locator('input[name="fcm_token"]').fill('fake-fcm-token');
  await page.locator('select[name="platform"]').selectOption('web');
  await page.locator('input[name="access_token"]').evaluate((el: HTMLInputElement) => {
    el.removeAttribute('required');
  });
  await page.getByRole('button', { name: /enregistrer le device/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});

test('422 champ invalide => erreur affichée', async ({ page }) => {
  await page.route('**/v1/devices', (route) => {
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'validation_error', title: 'Champ invalide', detail: 'fcm_token est requis' }),
    });
  });

  await page.goto('/devices/register');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="fcm_token"]').fill('bad');
  await page.locator('select[name="platform"]').selectOption('ios');
  await page.getByRole('button', { name: /enregistrer le device/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 422', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('validation_error');
});
