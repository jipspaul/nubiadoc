import { test, expect } from '@playwright/test';

test('render — /test/cabinet/info affiche le formulaire', async ({ page }) => {
  await page.goto('/test/cabinet/info');
  await expect(page.locator('#cabinet-info-form')).toBeVisible();
  await expect(page.locator('#cabinet-id')).toBeVisible();
  await expect(page.locator('button[type="submit"]')).toBeVisible();
});

test('happy path — GET 200 affiche les infos cabinet', async ({ page }) => {
  await page.route('**/v1/cabinets/cab_123/info', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        cabinet_id: 'cab_123',
        name: 'Cabinet Dentaire du Centre',
        address: '12 rue de la Paix, 75001 Paris',
        phone: '+33 1 23 45 67 89',
        email: 'contact@cabinet.fr',
        website: 'https://cabinet.fr',
        schedule: { monday: '09:00-18:00', tuesday: '09:00-18:00' },
        provider: { provider_id: 'prov_456', display_name: 'Dr. Martin' },
      }),
    });
  });

  await page.goto('/test/cabinet/info');
  await page.fill('#cabinet-id', 'cab_123');
  await page.click('button[type="submit"]');
  await expect(page.locator('#info-section')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#info-status-badge')).toContainText('HTTP 200');
  await expect(page.locator('#info-dl')).toContainText('Cabinet Dentaire du Centre');
  await expect(page.locator('#info-dl')).toContainText('Dr. Martin');
});

test('error path — GET 404 affiche le message cabinet introuvable', async ({ page }) => {
  await page.route('**/v1/cabinets/cab_unknown/info', (route) => {
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'cabinet_not_found' }),
    });
  });

  await page.goto('/test/cabinet/info');
  await page.fill('#cabinet-id', 'cab_unknown');
  await page.click('button[type="submit"]');
  await expect(page.locator('#info-section')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#info-status-badge')).toContainText('HTTP 404');
  await expect(page.locator('#info-error')).toBeVisible();
  await expect(page.locator('#info-error')).toContainText('404');
});
