import { test, expect } from '@playwright/test';

test('GET /login sans JWT — header contient "Se connecter" et "Créer un compte"', async ({ page }) => {
  await page.goto('/login');
  const nav = page.locator('#public-nav');
  await expect(nav).toContainText('Se connecter');
  await expect(nav).toContainText('Créer un compte');
});

test('GET /login avec JWT dans localStorage — header contient "Mon espace"', async ({ page }) => {
  await page.goto('/login');
  await page.evaluate(() => localStorage.setItem('nubia_jwt', 'tok'));
  await page.reload();
  const nav = page.locator('#public-nav');
  await expect(nav).toContainText('Mon espace');
});
