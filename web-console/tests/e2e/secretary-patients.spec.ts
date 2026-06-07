import { test, expect } from '@playwright/test';

test('render — /secretary/patients affiche le titre et la section liste', async ({ page }) => {
  // Page requires nubia_jwt cookie; without it it redirects to /auth/login.
  // Set a minimal cookie so Astro renders the page instead of redirecting.
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/patients');
  await expect(page.getByRole('heading', { name: 'Patients du cabinet', level: 1 })).toBeVisible();
  await expect(page.locator('#patients-status')).toBeVisible();
  await expect(page.locator('#patients-container')).toBeVisible();
});

test('error path — /secretary/patients affiche erreur réseau quand l\'API échoue', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/pro/cabinet/patients**', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.goto('/secretary/patients');
  // Client-side script fires immediately; 403 triggers the error message
  await expect(page.locator('#patients-status')).toContainText('403', { timeout: 5000 });
});
