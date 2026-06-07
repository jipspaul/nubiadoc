import { test, expect } from '@playwright/test';

test('le formulaire /test/scheduling/directions est visible avec les champs requis', async ({ page }) => {
  await page.goto('/test/scheduling/directions');
  await expect(page.locator('input[name="access_token"]')).toBeVisible();
  await expect(page.locator('input[name="appointment_id"]')).toBeVisible();
  await expect(page.locator('select[name="mode"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /charger itinéraire/i })).toBeVisible();
  await expect(page.locator('#result')).toBeVisible();
});

test('happy path => GET directions retourne 200, détails et deeplink visibles', async ({ page }) => {
  await page.route('**/v1/appointments/*/directions*', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        mode: 'car',
        duration_min: 12,
        distance_m: 5400,
        deeplink: 'https://maps.example.com/route?dest=48.8566,2.3522',
      }),
    });
  });

  await page.goto('/test/scheduling/directions');
  await page.locator('input[name="access_token"]').fill('fake-access-token');
  await page.locator('input[name="appointment_id"]').fill('00000000-0000-0000-0000-000000000001');
  await page.locator('select[name="mode"]').selectOption('car');
  await page.getByRole('button', { name: /charger itinéraire/i }).click();
  await expect(page.locator('#dir-deeplink')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#dir-deeplink')).toHaveAttribute('href', 'https://maps.example.com/route?dest=48.8566,2.3522');
  await expect(page.locator('#dir-mode')).toContainText('car');
  await expect(page.locator('#dir-duration')).toContainText('12');
});
