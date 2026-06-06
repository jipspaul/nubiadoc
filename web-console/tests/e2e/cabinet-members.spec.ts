import { test, expect } from '@playwright/test';

test('render — /cabinet/members affiche les formulaires liste, ajout et patch rôle', async ({ page }) => {
  await page.goto('/cabinet/members');
  await expect(page.locator('#members-list-form input[name="access_token"]')).toBeVisible();
  await expect(page.locator('#members-add-form input[name="email"]')).toBeVisible();
  await expect(page.locator('#members-add-form select[name="role"]')).toBeVisible();
  await expect(page.locator('#members-patch-form input[name="user_id"]')).toBeVisible();
  await expect(page.locator('#list-result')).toBeVisible();
  await expect(page.locator('#add-result')).toBeVisible();
  await expect(page.locator('#patch-result')).toBeVisible();
});

test('happy path — GET 200 liste les membres du cabinet', async ({ page }) => {
  await page.route('**/v1/cabinet/members', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        members: [
          { user_id: '00000000-0000-0000-0000-000000000001', email: 'dr.dupont@cabinet.fr', role: 'practitioner' },
          { user_id: '00000000-0000-0000-0000-000000000002', email: 'sec@cabinet.fr', role: 'secretary' },
        ],
      }),
    });
  });

  await page.goto('/cabinet/members');
  await page.locator('#members-list-form input[name="access_token"]').fill('admin-token');
  await page.locator('#members-list-form button[type="submit"]').click();
  await expect(page.locator('#list-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#list-result')).toContainText('dr.dupont@cabinet.fr');
});

test('error path — POST 409 email déjà utilisé affiché dans le résultat', async ({ page }) => {
  await page.route('**/v1/cabinet/members', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'email_taken' }),
    });
  });

  await page.goto('/cabinet/members');
  await page.locator('#members-add-form input[name="access_token"]').fill('admin-token');
  await page.locator('#members-add-form input[name="email"]').fill('existing@cabinet.fr');
  await page.locator('#members-add-form input[name="first_name"]').fill('Jean');
  await page.locator('#members-add-form input[name="last_name"]').fill('Martin');
  await page.locator('#members-add-form button[type="submit"]').click();
  await expect(page.locator('#add-result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#add-result')).toContainText('email_taken');
});
