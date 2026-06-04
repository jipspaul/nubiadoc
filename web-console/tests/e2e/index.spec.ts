import { test, expect } from '@playwright/test';

test('GET / sans session — page contient boutons "Se connecter" et "Créer un compte"', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('link', { name: 'Se connecter' }).first()).toBeVisible();
  await expect(page.getByRole('link', { name: 'Créer un compte' }).first()).toBeVisible();
});

test('GET / avec nubia_jwt en localStorage — "Vous êtes connecté" visible et lien /app présent', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => localStorage.setItem('nubia_jwt', 'tok'));
  await page.reload();
  await expect(page.locator('#cta-auth')).toBeVisible();
  await expect(page.locator('#cta-auth')).toContainText('Vous êtes connecté');
  await expect(page.locator('#cta-auth a[href="/app"]')).toBeVisible();
});
