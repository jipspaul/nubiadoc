import { test, expect } from '@playwright/test';

test('la page /marketplace/suggest affiche les sections de résultats', async ({ page }) => {
  await page.goto('/marketplace/suggest');
  await expect(page.locator('#specialties-section')).toBeVisible();
  await expect(page.locator('#acts-section')).toBeVisible();
});

test('taper "dent" affiche au moins une suggestion', async ({ page }) => {
  await page.goto('/marketplace/suggest');
  await page.fill('#suggest-input', 'dent');
  // Wait for debounce + API response
  await page.waitForTimeout(500);
  const specialtiesList = page.locator('#specialties-list');
  const actsList = page.locator('#acts-list');
  const hasSpecialty = await specialtiesList.locator('li').first().textContent();
  const hasAct = await actsList.locator('li').first().textContent();
  const gotResult = (hasSpecialty && hasSpecialty !== '—' && hasSpecialty !== 'Aucun résultat.')
    || (hasAct && hasAct !== '—' && hasAct !== 'Aucun résultat.');
  expect(gotResult).toBe(true);
});

test('effacer le champ remet les sections à vide', async ({ page }) => {
  await page.goto('/marketplace/suggest');
  await page.fill('#suggest-input', 'dent');
  await page.waitForTimeout(500);
  await page.fill('#suggest-input', '');
  await page.waitForTimeout(400);
  await expect(page.locator('#specialties-list')).toContainText('—');
  await expect(page.locator('#acts-list')).toContainText('—');
});
