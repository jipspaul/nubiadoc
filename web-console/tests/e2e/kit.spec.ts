import { test, expect } from '@playwright/test';

test('la page /test/kit se charge et affiche le titre', async ({ page }) => {
  await page.goto('/test/kit');
  await expect(page.locator('#kit-heading')).toBeVisible();
  await expect(page.locator('#kit-heading')).toContainText('Kit composants');
});

test('la page /test/kit affiche tous les 10 composants', async ({ page }) => {
  await page.goto('/test/kit');

  // Button
  await expect(page.locator('button.btn--primary').first()).toBeVisible();
  // Field
  await expect(page.locator('#demo-name')).toBeVisible();
  // Card
  await expect(page.locator('article.card').first()).toBeVisible();
  // Table
  await expect(page.locator('table.table')).toBeVisible();
  // Modal (dialog élément présent dans le DOM)
  await expect(page.locator('#demo-modal')).toBeAttached();
  // Tabs
  await expect(page.locator('[role="tab"]').first()).toBeVisible();
  // Toast
  await expect(page.locator('.toast').first()).toBeVisible();
  // Badge
  await expect(page.locator('.badge').first()).toBeVisible();
  // EmptyState
  await expect(page.locator('#demo-empty')).toBeVisible();
  // Spinner
  await expect(page.locator('#spinner-md')).toBeVisible();
});
