import { test, expect } from '@playwright/test';

test('render — /cabinet/members-invite affiche le formulaire d\'invitation', async ({ page }) => {
  await page.goto('/cabinet/members-invite');
  await expect(page.locator('#invite-form input[name="access_token"]')).toBeVisible();
  await expect(page.locator('#invite-form input[name="email"]')).toBeVisible();
  await expect(page.locator('#invite-form input[name="first_name"]')).toBeVisible();
  await expect(page.locator('#invite-form input[name="last_name"]')).toBeVisible();
  await expect(page.locator('#invite-form select[name="role"]')).toBeVisible();
  await expect(page.locator('#invite-form input[name="rpps"]')).toBeVisible();
  await expect(page.locator('#invite-result')).toBeVisible();
});

test('happy path — POST 201 affiche "Invitation envoyée"', async ({ page }) => {
  await page.route('**/v1/cabinet/members', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({
        user_id: '00000000-0000-0000-0000-000000000010',
        email: 'dr.nouveau@cabinet.fr',
        role: 'practitioner',
      }),
    });
  });

  await page.goto('/cabinet/members-invite');
  await page.locator('#invite-form input[name="access_token"]').fill('admin-token');
  await page.locator('#invite-form input[name="email"]').fill('dr.nouveau@cabinet.fr');
  await page.locator('#invite-form input[name="first_name"]').fill('Sophie');
  await page.locator('#invite-form input[name="last_name"]').fill('Dupont');
  await page.locator('#invite-form select[name="role"]').selectOption('practitioner');
  await page.locator('#invite-form button[type="submit"]').click();
  await expect(page.locator('#invite-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#invite-result')).toContainText('Invitation envoyée');
});

test('error path — POST 409 email_taken affiché dans le résultat', async ({ page }) => {
  await page.route('**/v1/cabinet/members', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'email_taken' }),
    });
  });

  await page.goto('/cabinet/members-invite');
  await page.locator('#invite-form input[name="access_token"]').fill('admin-token');
  await page.locator('#invite-form input[name="email"]').fill('existing@cabinet.fr');
  await page.locator('#invite-form input[name="first_name"]').fill('Jean');
  await page.locator('#invite-form input[name="last_name"]').fill('Martin');
  await page.locator('#invite-form select[name="role"]').selectOption('secretary');
  await page.locator('#invite-form button[type="submit"]').click();
  await expect(page.locator('#invite-result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#invite-result')).toContainText('email_taken');
});

test('error path — POST 403 forbidden affiché pour un non-admin', async ({ page }) => {
  await page.route('**/v1/cabinet/members', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/cabinet/members-invite');
  await page.locator('#invite-form input[name="access_token"]').fill('secretary-token');
  await page.locator('#invite-form input[name="email"]').fill('nouveau@cabinet.fr');
  await page.locator('#invite-form input[name="first_name"]').fill('Paul');
  await page.locator('#invite-form input[name="last_name"]').fill('Durand');
  await page.locator('#invite-form select[name="role"]').selectOption('practitioner');
  await page.locator('#invite-form button[type="submit"]').click();
  await expect(page.locator('#invite-result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#invite-result')).toContainText('forbidden');
});
