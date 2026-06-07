import { test, expect } from '@playwright/test';

// --- /cabinet/members (index) ---

test('render — /cabinet/members affiche les formulaires liste et ajout', async ({ page }) => {
  await page.goto('/cabinet/members');
  await expect(page.locator('#members-list-form input[name="access_token"]')).toBeVisible();
  await expect(page.locator('#members-add-form input[name="email"]')).toBeVisible();
  await expect(page.locator('#members-add-form select[name="role"]')).toBeVisible();
  await expect(page.locator('#list-result')).toBeVisible();
  await expect(page.locator('#add-result')).toBeVisible();
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

test('error path — GET 403 forbidden affiché pour un non-admin (secrétaire)', async ({ page }) => {
  await page.route('**/v1/cabinet/members', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/cabinet/members');
  await page.locator('#members-list-form input[name="access_token"]').fill('secretary-token');
  await page.locator('#members-list-form button[type="submit"]').click();
  await expect(page.locator('#list-result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#list-result')).toContainText('forbidden');
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

// --- /cabinet/members/[id] ---

test('render — /cabinet/members/[id] affiche les formulaires PATCH et DELETE', async ({ page }) => {
  await page.goto('/cabinet/members/00000000-0000-0000-0000-000000000001');
  await expect(page.locator('#member-patch-form input[name="user_id"]')).toBeVisible();
  await expect(page.locator('#member-patch-form select[name="role"]')).toBeVisible();
  await expect(page.locator('#member-delete-form input[name="user_id"]')).toBeVisible();
  await expect(page.locator('#patch-result')).toBeVisible();
  await expect(page.locator('#delete-result')).toBeVisible();
});

test('happy path — PATCH 200 change le rôle d\'un membre', async ({ page }) => {
  const memberId = '00000000-0000-0000-0000-000000000001';
  await page.route(`**/v1/cabinet/members/${memberId}`, (route) => {
    if (route.request().method() !== 'PATCH') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ user_id: memberId, role: 'admin' }),
    });
  });

  await page.goto(`/cabinet/members/${memberId}`);
  await page.locator('#member-patch-form input[name="access_token"]').fill('admin-token');
  await page.locator('#member-patch-form input[name="user_id"]').fill(memberId);
  await page.locator('#member-patch-form select[name="role"]').selectOption('admin');
  await page.locator('#member-patch-form button[type="submit"]').click();
  await expect(page.locator('#patch-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#patch-result')).toContainText('admin');
});

test('happy path — DELETE 204 désactive un membre', async ({ page }) => {
  const memberId = '00000000-0000-0000-0000-000000000002';
  await page.route(`**/v1/cabinet/members/${memberId}`, (route) => {
    if (route.request().method() !== 'DELETE') { route.continue(); return; }
    route.fulfill({ status: 204, body: '' });
  });

  await page.goto(`/cabinet/members/${memberId}`);
  await page.locator('#member-delete-form input[name="access_token"]').fill('admin-token');
  await page.locator('#member-delete-form input[name="user_id"]').fill(memberId);
  await page.locator('#member-delete-form button[type="submit"]').click();
  await expect(page.locator('#delete-result')).toContainText('HTTP 204', { timeout: 5000 });
});
