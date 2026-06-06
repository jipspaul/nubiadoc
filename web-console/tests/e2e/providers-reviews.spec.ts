import { test, expect } from '@playwright/test';

const PROVIDER_ID = '00000000-0000-0000-0000-000000000001';
const PAGE_URL = `/providers/${PROVIDER_ID}/reviews`;

test('la page /providers/[id]/reviews affiche le titre et le formulaire', async ({ page }) => {
  await page.route(`**/v1/providers/${PROVIDER_ID}/reviews**`, (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: [], rating_avg: null, page: { current: 1, per_page: 20, total: 0, total_pages: 1 } }),
    });
  });

  await page.goto(PAGE_URL);
  await expect(page.locator('h1')).toContainText('/v1/providers');
  await expect(page.locator('h1')).toContainText('/reviews');
  await expect(page.getByRole('button', { name: /charger les avis/i })).toBeVisible();
  await expect(page.locator('#reviews-table')).toBeVisible();
});

test('happy path : liste des avis affichée avec note moyenne', async ({ page }) => {
  await page.route(`**/v1/providers/${PROVIDER_ID}/reviews**`, (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: [
          { review_id: 'r1', rating: 5, comment: 'Excellent praticien', created_at: '2025-01-15T10:00:00Z' },
          { review_id: 'r2', rating: 4, comment: 'Très bien', created_at: '2025-01-14T09:00:00Z' },
        ],
        rating_avg: 4.5,
        page: { current: 1, per_page: 20, total: 2, total_pages: 1 },
      }),
    });
  });

  await page.goto(PAGE_URL);
  await expect(page.locator('#reviews-tbody')).toContainText('Excellent praticien', { timeout: 5000 });
  await expect(page.locator('#reviews-tbody')).toContainText('Très bien');
  await expect(page.locator('#rating-avg')).toContainText('4.5');
  await expect(page.locator('#status-badge')).toContainText('200');
});

test('pagination : bouton suivant charge la page 2', async ({ page }) => {
  await page.route(`**/v1/providers/${PROVIDER_ID}/reviews**`, (route) => {
    const url = new URL(route.request().url());
    const p = url.searchParams.get('page') ?? '1';
    if (p === '2') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: [{ review_id: 'r21', rating: 3, comment: 'Correct', created_at: '2024-12-01T08:00:00Z' }],
          rating_avg: 4.2,
          page: { current: 2, per_page: 20, total: 21, total_pages: 2 },
        }),
      });
    } else {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: Array.from({ length: 20 }, (_, i) => ({
            review_id: `r${i + 1}`, rating: 5, comment: `Avis ${i + 1}`, created_at: '2025-01-01T00:00:00Z',
          })),
          rating_avg: 4.9,
          page: { current: 1, per_page: 20, total: 21, total_pages: 2 },
        }),
      });
    }
  });

  await page.goto(PAGE_URL);
  await expect(page.locator('#page-info')).toContainText('Page 1 / 2', { timeout: 5000 });
  await page.getByRole('button', { name: /suiv/i }).click();
  await expect(page.locator('#page-info')).toContainText('Page 2 / 2', { timeout: 5000 });
  await expect(page.locator('#reviews-tbody')).toContainText('Correct');
});

test('404 sur provider inexistant', async ({ page }) => {
  const unknownId = '00000000-0000-0000-0000-000000000000';
  await page.route(`**/v1/providers/${unknownId}/reviews**`, (route) => {
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'provider_not_found' }),
    });
  });

  await page.goto(`/providers/${unknownId}/reviews`);
  await expect(page.locator('#not-found-msg')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#not-found-msg')).toContainText('404');
  await expect(page.locator('#status-badge')).toContainText('404');
});
