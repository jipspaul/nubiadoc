import { test, expect } from '@playwright/test';

test('render — /secretary/liste-attente affiche le titre et la section', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/liste-attente');
  await expect(page.getByRole('heading', { name: "Liste d'attente cabinet", level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Demandes en attente', level: 2 })).toBeVisible();
  await expect(page.locator('#list-status')).toBeVisible();
  await expect(page.getByRole('table', { name: "Liste d'attente cabinet" })).toBeVisible();
});

test("happy path — affiche les entrées retournées par l'API", async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/waiting-list**', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: '00000000-0000-0000-0000-000000000001',
          patient_id: 'pat-001',
          motif: 'Consultation générale',
          requested_at: '2026-06-01T08:00:00.000Z',
          status: 'waiting',
        },
      ]),
    });
  });
  await page.goto('/secretary/liste-attente');
  await expect(page.locator('#waiting-tbody')).toContainText('pat-001', { timeout: 5000 });
  await expect(page.locator('#waiting-badge')).toBeVisible({ timeout: 5000 });
});

test("error path — affiche erreur 403 quand l'API refuse l'accès", async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/waiting-list**', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.goto('/secretary/liste-attente');
  await expect(page.locator('#list-status')).toContainText('403', { timeout: 5000 });
});
