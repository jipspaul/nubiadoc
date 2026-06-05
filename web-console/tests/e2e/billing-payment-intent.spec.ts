import { test, expect } from '@playwright/test';

test('le formulaire /test/billing/payment-intent est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/billing/payment-intent');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="quote_id"]')).toBeVisible();
  await expect(page.locator('select[name="kind"]')).toBeVisible();
  await expect(page.locator('input[name="amount_cents"]')).toBeVisible();
  await expect(page.locator('select[name="method"]')).toBeVisible();
  await expect(page.locator('input[name="idempotency_key"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /créer l'intent/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('201 => POST valide retourne { payment_id, client_secret }', async ({ page }) => {
  await page.route('**/v1/payments/intent', (route) => {
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({
        payment_id: '00000000-0000-0000-0000-000000000001',
        client_secret: 'pi_test_secret_abc123',
      }),
    });
  });

  await page.goto('/test/billing/payment-intent');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="quote_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('select[name="kind"]').selectOption('deposit');
  await page.locator('input[name="amount_cents"]').fill('5000');
  await page.locator('select[name="method"]').selectOption('card');
  await page.locator('input[name="idempotency_key"]').fill('idem-key-001');
  await page.getByRole('button', { name: /créer l'intent/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('client_secret');
});

test('422 (clé idempotence manquante) => erreur affichée', async ({ page }) => {
  await page.route('**/v1/payments/intent', (route) => {
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'missing_idempotency_key' }),
    });
  });

  await page.goto('/test/billing/payment-intent');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="quote_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('select[name="kind"]').selectOption('full');
  await page.locator('input[name="amount_cents"]').fill('10000');
  await page.locator('select[name="method"]').selectOption('sepa');
  await page.locator('input[name="idempotency_key"]').fill('any-key');
  await page.getByRole('button', { name: /créer l'intent/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 422', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('missing_idempotency_key');
});

test('401 => accès non autorisé affiché', async ({ page }) => {
  await page.route('**/v1/payments/intent', (route) => {
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthorized' }),
    });
  });

  await page.goto('/test/billing/payment-intent');
  await page.locator('input[name="access_token"]').fill('bad-token');
  await page.locator('input[name="quote_id"]').fill('00000000-0000-0000-0000-000000000002');
  await page.locator('select[name="kind"]').selectOption('deposit');
  await page.locator('input[name="amount_cents"]').fill('5000');
  await page.locator('select[name="method"]').selectOption('card');
  await page.locator('input[name="idempotency_key"]').fill('idem-key-002');
  await page.getByRole('button', { name: /créer l'intent/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 401', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('unauthorized');
});
