import { test, expect } from '@playwright/test';

test('le formulaire /test/messaging/create-conversation est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/messaging/create-conversation');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="cabinet_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /démarrer \/ retrouver fil/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('POST cabinet_id valide => 201 + conversation_id affiché', async ({ page }) => {
  await page.route('**/v1/conversations', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ conversation_id: '00000000-0000-0000-0000-000000000001', existing: false }),
    });
  });

  await page.goto('/test/messaging/create-conversation');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="cabinet_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.getByRole('button', { name: /démarrer \/ retrouver fil/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('conversation_id');
  await expect(page.locator('#conversation-id')).toContainText('00000000-0000-0000-0000-000000000001');
  await expect(page.locator('#existing-flag')).toContainText('false');
});

test('re-POST même cabinet_id => 200 + même conversation_id + existing: true', async ({ page }) => {
  await page.route('**/v1/conversations', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ conversation_id: '00000000-0000-0000-0000-000000000001', existing: true }),
    });
  });

  await page.goto('/test/messaging/create-conversation');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="cabinet_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.getByRole('button', { name: /démarrer \/ retrouver fil/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#existing-flag')).toContainText('true');
  await expect(page.locator('#conversation-id')).toContainText('00000000-0000-0000-0000-000000000001');
});

test('cabinet_id inexistant => 404 affiché', async ({ page }) => {
  await page.route('**/v1/conversations', (route) => {
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found', title: 'Cabinet introuvable' }),
    });
  });

  await page.goto('/test/messaging/create-conversation');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="cabinet_id"]').fill('00000000-0000-0000-0000-000000000099');
  await page.getByRole('button', { name: /démarrer \/ retrouver fil/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 404', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('not_found');
});
