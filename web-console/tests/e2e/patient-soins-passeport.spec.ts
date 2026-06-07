import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/soins/passeport affiche le titre et le loading', async ({ page }) => {
  // Block API so loading stays visible
  await page.route('**/v1/implant-passport', (route) => new Promise(() => {}));
  await page.goto('/patient/soins/passeport');
  await expect(page.getByRole('heading', { name: /passeport implant/i })).toBeVisible();
  await expect(page.locator('#passport-loading')).toBeVisible();
  await expect(page.getByRole('button', { name: /exporter le passeport/i })).toBeVisible();
});

// ─── happy path — implants chargés ─────────────────────────────────────────

test('happy path — implants chargés : lignes visibles dans le tableau', async ({ page }) => {
  await page.route('**/v1/implant-passport', (route) => {
    if (route.request().method() === 'GET' && !route.request().url().includes('/export')) {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          implants: [
            { type: 'Implant titane', position: '46', placed_at: '2025-03-10T00:00:00Z' },
            { type: 'Implant zircone', position: '26', placed_at: '2025-11-01T00:00:00Z' },
          ],
        }),
      });
    } else {
      route.continue();
    }
  });
  await page.goto('/patient/soins/passeport');

  await expect(page.locator('#implants-table')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#implants-tbody')).toContainText('Implant titane');
  await expect(page.locator('#implants-tbody')).toContainText('46');
  await expect(page.locator('#implants-tbody')).toContainText('Implant zircone');
  await expect(page.locator('#passport-loading')).toBeHidden();
});

// ─── error path — API 401 ─────────────────────────────────────────────────

test('error path — API 401 : message d\'erreur affiché', async ({ page }) => {
  await page.route('**/v1/implant-passport', (route) => {
    if (!route.request().url().includes('/export')) {
      route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({ code: 'unauthenticated' }),
      });
    } else {
      route.continue();
    }
  });
  await page.goto('/patient/soins/passeport');
  await expect(page.locator('#passport-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#passport-error')).toContainText(/impossible/i);
  await expect(page.locator('#implants-table')).toBeHidden();
});
