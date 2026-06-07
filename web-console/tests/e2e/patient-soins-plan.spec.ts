import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/soins/plan affiche le titre et le loading', async ({ page }) => {
  // Block API so loading stays visible
  await page.route('**/v1/treatment-plans', (route) => new Promise(() => {}));
  await page.goto('/patient/soins/plan');
  await expect(page.getByRole('heading', { name: /plan de traitement/i })).toBeVisible();
  await expect(page.locator('#plans-loading')).toBeVisible();
});

// ─── happy path — liste chargée ────────────────────────────────────────────

test('happy path — plans chargés : items visibles dans la liste', async ({ page }) => {
  await page.route('**/v1/treatment-plans', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: 'plan-001',
          title: 'Plan implants 2026',
          status: 'active',
          created_at: '2026-01-15T10:00:00Z',
        },
        {
          id: 'plan-002',
          title: 'Soins orthodontie',
          status: 'termine',
          created_at: '2025-06-01T08:00:00Z',
        },
      ]),
    }),
  );
  await page.goto('/patient/soins/plan');

  const item1 = page.locator('[data-plan-id="plan-001"]');
  await expect(item1).toBeVisible({ timeout: 5000 });
  await expect(item1).toContainText('Plan implants 2026');
  await expect(item1).toContainText('active');

  const item2 = page.locator('[data-plan-id="plan-002"]');
  await expect(item2).toBeVisible();
  await expect(item2).toContainText('Soins orthodontie');

  await expect(page.locator('#plans-loading')).toBeHidden();
});

// ─── error path — API 500 ─────────────────────────────────────────────────

test('error path — API 500 : message d\'erreur affiché', async ({ page }) => {
  await page.route('**/v1/treatment-plans', (route) =>
    route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'internal_server_error' }),
    }),
  );
  await page.goto('/patient/soins/plan');
  await expect(page.locator('#plans-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#plans-error')).toContainText(/impossible/i);
  await expect(page.locator('#plans-list')).toBeHidden();
});
