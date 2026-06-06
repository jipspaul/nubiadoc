import { test, expect } from '@playwright/test';

test('le formulaire /me est visible avec les champs requis', async ({ page }) => {
  await page.goto('/me');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /get/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path : profil patient affiché', async ({ page }) => {
  await page.route('**/v1/me', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        user_id: 'usr-patient-123',
        email: 'patient@example.com',
        kind: 'patient',
        account_id: 'acc-456',
        memberships: [],
      }),
    }),
  );

  await page.goto('/me');
  await page.locator('input[name="access_token"]').fill('valid-patient-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#field-user_id')).toContainText('usr-patient-123');
  await expect(page.locator('#field-email')).toContainText('patient@example.com');
  await expect(page.locator('#field-kind')).toContainText('patient');
  await expect(page.locator('#field-account_id')).toContainText('acc-456');
});

test('profil pro avec memberships affiché', async ({ page }) => {
  await page.route('**/v1/me', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        user_id: 'usr-pro-789',
        email: 'pro@example.com',
        kind: 'pro',
        memberships: [
          { cabinet_id: 'cab-001', role: 'admin' },
          { cabinet_id: 'cab-002', role: 'practitioner' },
        ],
      }),
    }),
  );

  await page.goto('/me');
  await page.locator('input[name="access_token"]').fill('valid-pro-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#field-kind')).toContainText('pro');
  await expect(page.locator('#memberships-section')).toBeVisible();
  await expect(page.locator('#memberships-body')).toContainText('cab-001');
  await expect(page.locator('#memberships-body')).toContainText('admin');
});

test('401 sans token valide → erreur affichée', async ({ page }) => {
  await page.route('**/v1/me', route =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({
        type: 'https://nubia.health/errors/unauthenticated',
        title: 'Token invalide ou absent',
        status: 401,
        code: 'unauthenticated',
      }),
    }),
  );

  await page.goto('/me');
  await page.locator('input[name="access_token"]').fill('invalid-token');
  await page.getByRole('button', { name: /get/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
});
