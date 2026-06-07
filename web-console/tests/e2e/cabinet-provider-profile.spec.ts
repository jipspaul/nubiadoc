import { test, expect } from '@playwright/test';

test('render — /cabinet/provider-profile affiche le formulaire de profil', async ({ page }) => {
  await page.goto('/cabinet/provider-profile');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('textarea[name="bio"]')).toBeVisible();
  await expect(page.locator('select[name="sector"]')).toBeVisible();
  await expect(page.locator('input[name="acts"]').first()).toBeVisible();
  await expect(page.locator('input[name="languages"]').first()).toBeVisible();
  await expect(page.locator('input[name="pmr"]')).toBeVisible();
  await expect(page.locator('input[name="photo"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /patch/i })).toBeVisible();
  await expect(page.locator('#profile-result')).toBeVisible();
});

test('happy path — PATCH 200 met à jour les champs du profil', async ({ page }) => {
  await page.route('**/v1/cabinet/provider', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        bio: 'Chirurgien-dentiste spécialisé en implantologie.',
        sector: '2',
        acts: ['consultation', 'implant'],
        languages: ['fr', 'en'],
        pmr: true,
      }),
    });
  });

  await page.goto('/cabinet/provider-profile');
  await page.locator('input[name="access_token"]').fill('pro-token');
  await page.locator('textarea[name="bio"]').fill('Chirurgien-dentiste spécialisé en implantologie.');
  await page.locator('select[name="sector"]').selectOption('2');
  await page.locator('input[name="acts"][value="consultation"]').check();
  await page.locator('input[name="acts"][value="implant"]').check();
  await page.locator('input[name="languages"][value="fr"]').check();
  await page.locator('input[name="pmr"]').check();
  await page.getByRole('button', { name: /patch/i }).click();

  await expect(page.locator('#profile-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#profile-result')).toContainText('bio');
  await expect(page.locator('#profile-result')).toContainText('implantologie');
});

test('error path — PATCH 403 avec token secrétaire affiche forbidden', async ({ page }) => {
  await page.route('**/v1/cabinet/provider', (route) => {
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden', message: 'Secretary role is not allowed to edit provider profile' }),
    });
  });

  await page.goto('/cabinet/provider-profile');
  await page.locator('input[name="access_token"]').fill('secretary-token');
  await page.locator('textarea[name="bio"]').fill('test');
  await page.getByRole('button', { name: /patch/i }).click();

  await expect(page.locator('#profile-result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#profile-result')).toContainText('forbidden');
});
