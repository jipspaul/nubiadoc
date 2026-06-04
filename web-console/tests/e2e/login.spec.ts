import { test, expect } from '@playwright/test';

test('le formulaire /login est visible avec les champs et le bouton', async ({ page }) => {
  await page.goto('/login');
  await expect(page.locator('input[name="email"]')).toBeVisible();
  await expect(page.locator('input[name="password"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('submit avec champs vides reste sur /login et affiche une erreur', async ({ page }) => {
  await page.goto('/login');
  // Retire les attributs required pour que la soumission atteigne l'API (HTTP 422 attendu)
  await page.evaluate(() => {
    document.querySelectorAll('#login-form input[required]').forEach(el =>
      el.removeAttribute('required'),
    );
  });
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/login');
});

test('submit avec credentials bidon affiche une erreur API ou réseau', async ({ page }) => {
  await page.goto('/login');
  await page.locator('input[name="email"]').fill('fake@example.com');
  await page.locator('input[name="password"]').fill('wrongpassword');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/login');
});
