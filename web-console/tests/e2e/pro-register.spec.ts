import { test, expect } from '@playwright/test';

test('la page /pro/register affiche le formulaire avec tous les champs requis', async ({ page }) => {
  await page.goto('/pro/register');
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="password"]')).toBeVisible();
  await expect(page.locator('input[name="cabinet_raison_sociale"]')).toBeVisible();
  await expect(page.locator('input[name="cabinet_specialite"]')).toBeVisible();
  await expect(page.locator('input[name="first_name"]')).toBeVisible();
  await expect(page.locator('input[name="last_name"]')).toBeVisible();
  await expect(page.locator('input[name="rpps"]')).toBeVisible();
  await expect(page.locator('input[name="accept_cgu"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /créer le compte pro/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('201 — données valides avec CGU acceptées affiche cabinet_id', async ({ page }) => {
  await page.route('**/v1/pro/register', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({
        account_id: '00000000-0000-0000-0000-000000000001',
        cabinet_id: '00000000-0000-0000-0000-000000000002',
        provider_id: '00000000-0000-0000-0000-000000000003',
        access_token: 'eyJhbGciOiJIUzI1NiJ9.test',
      }),
    });
  });

  await page.goto('/pro/register');
  await page.locator('input[name="email"]').fill('dr.dupont@example.com');
  await page.locator('input[name="password"]').fill('SecurePass123!');
  await page.locator('input[name="cabinet_raison_sociale"]').fill('Cabinet Dr Dupont');
  await page.locator('input[name="cabinet_specialite"]').fill('medecine_generale');
  await page.locator('input[name="first_name"]').fill('Jean');
  await page.locator('input[name="last_name"]').fill('Dupont');
  await page.locator('input[name="accept_cgu"]').check();
  await page.getByRole('button', { name: /créer le compte pro/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('cabinet_id');
});

test('409 — email déjà pris affiche email_taken', async ({ page }) => {
  await page.route('**/v1/pro/register', (route) => {
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'email_taken' }),
    });
  });

  await page.goto('/pro/register');
  await page.locator('input[name="email"]').fill('already@example.com');
  await page.locator('input[name="password"]').fill('SecurePass123!');
  await page.locator('input[name="cabinet_raison_sociale"]').fill('Cabinet Test');
  await page.locator('input[name="cabinet_specialite"]').fill('medecine_generale');
  await page.locator('input[name="first_name"]').fill('Jean');
  await page.locator('input[name="last_name"]').fill('Dupont');
  await page.locator('input[name="accept_cgu"]').check();
  await page.getByRole('button', { name: /créer le compte pro/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('email_taken');
});

test('422 — sans accepter les CGU envoie accept_cgu:false → cgu_required', async ({ page }) => {
  await page.route('**/v1/pro/register', (route) => {
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'cgu_required' }),
    });
  });

  await page.goto('/pro/register');
  await page.locator('input[name="email"]').fill('new@example.com');
  await page.locator('input[name="password"]').fill('SecurePass123!');
  await page.locator('input[name="cabinet_raison_sociale"]').fill('Cabinet Test');
  await page.locator('input[name="cabinet_specialite"]').fill('medecine_generale');
  await page.locator('input[name="first_name"]').fill('Jean');
  await page.locator('input[name="last_name"]').fill('Dupont');
  // accept_cgu intentionally left unchecked
  await page.getByRole('button', { name: /créer le compte pro/i }).click();

  await expect(page.locator('#result')).toContainText('HTTP 422', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('cgu_required');
});
