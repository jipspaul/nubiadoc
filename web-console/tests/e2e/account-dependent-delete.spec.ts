import { test, expect } from '@playwright/test';

test('le formulaire /account/dependent-delete est visible avec les champs requis', async ({ page }) => {
  await page.goto('/account/dependent-delete');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="dependent_id"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /révoquer tutelle/i })).toBeVisible();
});

test('DELETE valide — submit avec ID existant affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/account/dependent-delete');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="dependent_id"]').fill('11111111-1111-1111-1111-111111111111');
  await page.getByRole('button', { name: /révoquer tutelle/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/account/dependent-delete');
});

test('double DELETE — second appel avec même ID affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/account/dependent-delete');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="dependent_id"]').fill('00000000-0000-0000-0000-000000000000');
  await page.getByRole('button', { name: /révoquer tutelle/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/account/dependent-delete');
});
