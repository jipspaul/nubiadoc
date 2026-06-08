import { test, expect } from '@playwright/test';

test('redirect — /secretary/dashboard sans nubia_ctx redirige vers /auth/select-context', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
    // nubia_ctx absent → pas de secretariat_id
  ]);
  await page.goto('/secretary/dashboard');
  await expect(page).toHaveURL(/\/auth\/select-context/);
});

test('redirect — /secretary/dashboard avec nubia_ctx sans secretariat_id redirige vers /auth/select-context', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
    // cabinet_id|role| avec secretariat_id vide
    { name: 'nubia_ctx', value: 'cab-001|secretary|', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/dashboard');
  await expect(page).toHaveURL(/\/auth\/select-context/);
});

test('pass — /secretary/dashboard avec nubia_ctx portant un secretariat_id valide accède à la page', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
    { name: 'nubia_ctx', value: 'cab-001|secretary|sec-001', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/dashboard');
  await expect(page).not.toHaveURL(/\/auth\/select-context/);
});
