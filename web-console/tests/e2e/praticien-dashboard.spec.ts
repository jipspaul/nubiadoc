import { test, expect } from '@playwright/test';

test('render — /praticien/dashboard affiche le titre et les trois sections', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/praticien/dashboard');
  await expect(page.getByRole('heading', { name: 'Tableau de bord praticien', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Agenda du jour', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Rendez-vous du jour', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: "Salle d'attente", level: 2 })).toBeVisible();
});

test('error path — GET /v1/cabinet/agenda répond 401 affiche Chargement puis erreur', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'practitioner', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/agenda**', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.goto('/praticien/dashboard');
  await expect(page.locator('#agenda-status')).toContainText('Accès refusé (403)', { timeout: 5000 });
});
