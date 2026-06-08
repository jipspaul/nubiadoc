import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/documents affiche le titre et le loading', async ({ page }) => {
  // Block API so loading state stays visible
  await page.route('**/v1/documents', () => new Promise(() => {}));
  await page.goto('/patient/documents');
  await expect(page.getByRole('heading', { name: /mes documents/i })).toBeVisible();
  await expect(page.locator('#docs-loading')).toBeVisible();
});

// ─── happy path — liste chargée ────────────────────────────────────────────

test('happy path — documents chargés : cartes visibles avec liens de détail', async ({ page }) => {
  await page.route('**/v1/documents', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: 'doc-aaa',
          name: 'Radio panoramique',
          type: 'radiographie',
          created_at: '2026-04-15T08:30:00Z',
        },
        {
          id: 'doc-bbb',
          name: 'Ordonnance amoxicilline',
          type: 'ordonnance',
          created_at: '2026-05-01T09:00:00Z',
        },
      ]),
    }),
  );
  await page.goto('/patient/documents');

  await expect(page.locator('#docs-list')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#docs-loading')).toBeHidden();

  await expect(page.getByRole('link', { name: /voir/i }).first()).toBeVisible();

  const firstCard = page.locator('.doc-card').first();
  await expect(firstCard).toContainText('Radio panoramique');
  await expect(firstCard).toContainText('radiographie');
});

// ─── empty state ────────────────────────────────────────────────────────────

test('empty — liste vide affiche "Aucun document enregistré"', async ({ page }) => {
  await page.route('**/v1/documents', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
  );
  await page.goto('/patient/documents');
  await expect(page.locator('#docs-empty')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#docs-empty')).toContainText(/aucun document/i);
  await expect(page.locator('#docs-list')).toBeHidden();
});

// ─── error path — API 500 ─────────────────────────────────────────────────

test('error path — API 500 : message d\'erreur affiché, liste masquée', async ({ page }) => {
  await page.route('**/v1/documents', (route) =>
    route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'internal_server_error' }),
    }),
  );
  await page.goto('/patient/documents');
  await expect(page.locator('#docs-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#docs-error')).toContainText(/impossible/i);
  await expect(page.locator('#docs-list')).toBeHidden();
});
