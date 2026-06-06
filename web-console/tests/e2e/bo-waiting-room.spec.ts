import { test, expect } from '@playwright/test';

// --- waiting-room page ---

test('waiting-room: page rendue avec les deux formulaires', async ({ page }) => {
  await page.goto('/cabinet/waiting-room');
  await expect(page.locator('h1')).toBeVisible();
  await expect(page.locator('#waiting-room-form input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /charger la file/i })).toBeVisible();
  await expect(page.locator('#room-result')).toBeVisible();
  await expect(page.locator('#call-next-form input[name="access_token_cn"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /appeler le suivant/i })).toBeVisible();
  await expect(page.locator('#cn-result')).toBeVisible();
});

test('waiting-room: GET 200 affiche la file dans le résultat', async ({ page }) => {
  await page.route('**/v1/cabinet/waiting-room', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ queue: [{ id: 'patient-uuid-1', display_name: 'Alice Martin' }] }),
    });
  });

  await page.goto('/cabinet/waiting-room');
  await page.locator('#waiting-room-form input[name="access_token"]').fill('fake-token');
  await page.getByRole('button', { name: /charger la file/i }).click();
  await expect(page.locator('#room-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#room-result')).toContainText('Alice Martin');
});

test('waiting-room: POST call-next 200 avec patient affiché', async ({ page }) => {
  await page.route('**/v1/cabinet/waiting-room/call-next', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ patient: { id: 'patient-uuid-1', display_name: 'Bob Dupont' } }),
    });
  });

  await page.goto('/cabinet/waiting-room');
  await page.locator('#call-next-form input[name="access_token_cn"]').fill('fake-token');
  await page.getByRole('button', { name: /appeler le suivant/i }).click();
  await expect(page.locator('#cn-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#cn-result')).toContainText('Bob Dupont');
});

// --- waiting-list page ---

test('waiting-list: page rendue avec les deux formulaires', async ({ page }) => {
  await page.goto('/cabinet/waiting-list');
  await expect(page.locator('h1')).toBeVisible();
  await expect(page.locator('#waiting-list-form input[name="access_token"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /charger la liste/i })).toBeVisible();
  await expect(page.locator('#list-result')).toBeVisible();
  await expect(page.locator('#offer-form input[name="entry_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /proposer un créneau/i })).toBeVisible();
  await expect(page.locator('#offer-result')).toBeVisible();
});

test('waiting-list: GET 200 affiche la liste', async ({ page }) => {
  await page.route('**/v1/cabinet/waiting-list', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ entries: [{ id: 'entry-uuid-1', patient: { display_name: 'Claire Morin' } }] }),
    });
  });

  await page.goto('/cabinet/waiting-list');
  await page.locator('#waiting-list-form input[name="access_token"]').fill('fake-token');
  await page.getByRole('button', { name: /charger la liste/i }).click();
  await expect(page.locator('#list-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#list-result')).toContainText('Claire Morin');
});

test('waiting-list: POST offer 201 affiche le statut', async ({ page }) => {
  await page.route('**/v1/cabinet/waiting-list/entry-uuid-1/offer', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ offer_id: 'offer-uuid-1', status: 'sent' }),
    });
  });

  await page.goto('/cabinet/waiting-list');
  await page.locator('#offer-form input[name="access_token_offer"]').fill('fake-token');
  await page.locator('#offer-form input[name="entry_id"]').fill('entry-uuid-1');
  await page.getByRole('button', { name: /proposer un créneau/i }).click();
  await expect(page.locator('#offer-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#offer-result')).toContainText('sent');
});
