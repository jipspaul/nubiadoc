import { test, expect } from '@playwright/test';

test('render : /test/pro-onboarding affiche les trois formulaires', async ({ page }) => {
  await page.goto('/test/pro-onboarding');
  // Section 1 — register
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="password"]')).toBeVisible();
  await expect(page.locator('input[name="cabinet_raison_sociale"]')).toBeVisible();
  await expect(page.locator('input[name="first_name"]')).toBeVisible();
  await expect(page.locator('input[name="last_name"]')).toBeVisible();
  await expect(page.locator('#register-result')).toBeVisible();
  // Section 2 — verification POST
  await expect(page.locator('#verification-result')).toBeVisible();
  // Section 3 — statut GET
  await expect(page.locator('#status-result')).toBeVisible();
});

test('register : 201 affiche account_id, cabinet_id et provider_id', async ({ page }) => {
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

  await page.goto('/test/pro-onboarding');
  await page.locator('input[name="email"]').fill('dr.test@example.com');
  await page.locator('input[name="password"]').fill('SecurePass123!');
  await page.locator('input[name="cabinet_raison_sociale"]').fill('Cabinet Dr Test');
  await page.locator('input[name="cabinet_specialite"]').fill('medecine_generale');
  await page.locator('input[name="first_name"]').fill('Marie');
  await page.locator('input[name="last_name"]').fill('Test');
  await page.locator('input[name="accept_cgu"]').check();
  await page.locator('#register-form button[type="submit"]').click();

  await expect(page.locator('#register-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#register-result')).toContainText('cabinet_id');
  await expect(page.locator('#register-result')).toContainText('provider_id');
  await expect(page.locator('#register-result')).toContainText('account_id');
});

test('verification : POST RPPS retourne status pending', async ({ page }) => {
  await page.route('**/v1/pro/verification', (route) => {
    if (route.request().method() === 'POST') {
      route.fulfill({
        status: 202,
        contentType: 'application/json',
        body: JSON.stringify({
          verification_id: 'verif-00000000-0001',
          status: 'pending',
        }),
      });
    } else {
      route.continue();
    }
  });

  await page.goto('/test/pro-onboarding');
  // Fill verification form (second form on the page)
  const verificationForms = page.locator('#verification-form');
  await verificationForms.locator('input[name="access_token"]').fill('eyJhbGciOiJIUzI1NiJ9.test');
  await verificationForms.locator('select[name="id_type"]').selectOption('rpps');
  await verificationForms.locator('input[name="identifier"]').fill('12345678901');
  await verificationForms.locator('button[type="submit"]').click();

  await expect(page.locator('#verification-result')).toContainText('HTTP 202', { timeout: 5000 });
  await expect(page.locator('#verification-result')).toContainText('pending');
});
