import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/devis affiche le titre et le loading', async ({ page }) => {
  // Block API so loading state stays visible
  await page.route('**/v1/quotes', (route) => new Promise(() => {}));
  await page.goto('/patient/devis');
  await expect(page.getByRole('heading', { name: /mes devis/i })).toBeVisible();
  await expect(page.locator('#quotes-loading')).toBeVisible();
});

// ─── happy path — liste chargée ────────────────────────────────────────────

test('happy path — devis chargés : cartes visibles dans la liste', async ({ page }) => {
  await page.route('**/v1/quotes', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: 'devis-001',
          status: 'pending',
          amount_cents: 120000,
          created_at: '2026-03-10T09:00:00Z',
        },
        {
          id: 'devis-002',
          status: 'signed',
          amount_cents: 85000,
          created_at: '2025-12-01T08:00:00Z',
        },
      ]),
    }),
  );
  await page.goto('/patient/devis');

  const card1 = page.locator('[data-quote-id="devis-001"]');
  await expect(card1).toBeVisible({ timeout: 5000 });
  await expect(card1).toContainText('devis-001');
  await expect(card1).toContainText('pending');

  const card2 = page.locator('[data-quote-id="devis-002"]');
  await expect(card2).toBeVisible();
  await expect(card2).toContainText('signed');

  await expect(page.locator('#quotes-loading')).toBeHidden();
});

// ─── error path — API 500 ────────────────────────────────────────────────

test('error path — API 500 : message d\'erreur affiché', async ({ page }) => {
  await page.route('**/v1/quotes', (route) =>
    route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'internal_server_error' }),
    }),
  );
  await page.goto('/patient/devis');
  await expect(page.locator('#quotes-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#quotes-error')).toContainText(/impossible/i);
  await expect(page.locator('#quotes-list')).toBeHidden();
});
