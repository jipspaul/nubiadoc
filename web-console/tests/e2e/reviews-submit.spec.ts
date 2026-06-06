import { test, expect } from '@playwright/test';

test('le formulaire /reviews/submit est visible avec les champs requis', async ({ page }) => {
  await page.goto('/reviews/submit');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.locator('input[name="rating"][value="5"]')).toBeVisible();
  await expect(page.locator('textarea[name="comment"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /déposer l'avis/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => POST /v1/reviews retourne 201 { review_id, status:"pending" }', async ({ page }) => {
  await page.route('**/v1/reviews', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ review_id: '00000000-0000-0000-0000-000000000099', status: 'pending' }),
    });
  });

  await page.goto('/reviews/submit');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('input[name="rating"][value="5"]').check();
  await page.locator('textarea[name="comment"]').fill('Excellent praticien, très professionnel.');
  await page.getByRole('button', { name: /déposer l'avis/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('review_id');
  await expect(page.locator('#result')).toContainText('pending');
});

test('double soumission => POST /v1/reviews retourne 409 (idempotence)', async ({ page }) => {
  await page.route('**/v1/reviews', (route) => {
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'review_already_submitted' }),
    });
  });

  await page.goto('/reviews/submit');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('input[name="rating"][value="4"]').check();
  await page.getByRole('button', { name: /déposer l'avis/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('review_already_submitted');
});

test('sans JWT => POST /v1/reviews retourne 401', async ({ page }) => {
  await page.route('**/v1/reviews', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/reviews/submit');
  await page.locator('input[name="access_token"]').fill('');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('input[name="rating"][value="3"]').check();
  await page.getByRole('button', { name: /déposer l'avis/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});
