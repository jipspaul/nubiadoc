import { test, expect } from '@playwright/test';

test('la page /webhooks/stripe est visible avec les champs requis', async ({ page }) => {
  await page.goto('/webhooks/stripe');
  await expect(page.locator('input[name="stripe_signature"]')).toBeVisible();
  await expect(page.locator('select[name="event_type"]')).toBeVisible();
  await expect(page.locator('input[name="event_id"]')).toBeVisible();
  await expect(page.locator('input[name="payment_intent_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer le webhook/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('200 => webhook valide affiche la réponse HTTP 200', async ({ page }) => {
  await page.route('**/v1/webhooks/stripe', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ received: true }),
    });
  });

  await page.goto('/webhooks/stripe');
  await page.locator('input[name="stripe_signature"]').fill('t=1234567890,v1=valid_sig');
  await page.locator('select[name="event_type"]').selectOption('payment_intent.succeeded');
  await page.locator('input[name="event_id"]').fill('evt_00000000000001');
  await page.locator('input[name="payment_intent_id"]').fill('pi_00000000000001');
  await page.getByRole('button', { name: /envoyer le webhook/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('received');
});

test('400 => signature invalide affiche l\'erreur', async ({ page }) => {
  await page.route('**/v1/webhooks/stripe', (route) => {
    route.fulfill({
      status: 400,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'invalid_signature' }),
    });
  });

  await page.goto('/webhooks/stripe');
  await page.locator('input[name="stripe_signature"]').fill('t=bad,v1=bad_sig');
  await page.locator('select[name="event_type"]').selectOption('payment_intent.payment_failed');
  await page.locator('input[name="event_id"]').fill('evt_00000000000002');
  await page.locator('input[name="payment_intent_id"]').fill('pi_00000000000002');
  await page.getByRole('button', { name: /envoyer le webhook/i }).click();
  await expect(page.locator('#result')).toContainText('HTTP 400', { timeout: 5000 });
  await expect(page.locator('#result')).toContainText('invalid_signature');
});
