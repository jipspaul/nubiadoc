import { test, expect } from '@playwright/test';

test('le formulaire /account/dependent-patch est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/account/dependent-patch');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="dependent_id"]')).toBeVisible();
  await expect(page.locator('input[name="first_name"]')).toBeVisible();
  await expect(page.locator('input[name="last_name"]')).toBeVisible();
  await expect(page.locator('input[name="birth_date"]')).toBeVisible();
  await expect(page.locator('select[name="relationship"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

test('PATCH valide — submit avec ID existant affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/account/dependent-patch');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="dependent_id"]').fill('11111111-1111-1111-1111-111111111111');
  await page.locator('input[name="first_name"]').fill('Bobby');
  await page.locator('input[name="last_name"]').fill('Updated');
  await page.locator('input[name="birth_date"]').fill('2016-06-15');
  await page.locator('select[name="relationship"]').selectOption('enfant');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/account/dependent-patch');
});

test('ID inconnu — submit avec UUID aléatoire affiche un résultat (status visible)', async ({ page }) => {
  await page.goto('/test/account/dependent-patch');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="dependent_id"]').fill('00000000-0000-0000-0000-000000000000');
  await page.getByRole('button', { name: /envoyer/i }).click();
  await expect(page.locator('#result')).toContainText(/Erreur réseau|HTTP/, { timeout: 5000 });
  await expect(page).toHaveURL('/test/account/dependent-patch');
});
