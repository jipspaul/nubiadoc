import { test, expect } from '@playwright/test';

test('render — /secretary/equipe affiche le titre et le formulaire d\'invitation', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/equipe');
  await expect(page.getByRole('heading', { name: 'Membres du cabinet', level: 1 })).toBeVisible();
  await expect(page.locator('#invite-form')).toBeVisible();
  await expect(page.locator('#invite-email')).toBeVisible();
  await expect(page.locator('#invite-role')).toBeVisible();
});

test('error path — affiche erreur 403 si l\'API refuse l\'accès membres', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/members', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.goto('/secretary/equipe');
  await expect(page.locator('#members-status')).toContainText('403', { timeout: 5000 });
});
