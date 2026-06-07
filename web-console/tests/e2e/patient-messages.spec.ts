import { test, expect } from '@playwright/test';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/messages affiche le titre et le loading', async ({ page }) => {
  // Block API so loading stays visible
  await page.route('**/v1/conversations', (route) => new Promise(() => {}));
  await page.goto('/patient/messages');
  await expect(page.getByRole('heading', { name: /mes messages/i })).toBeVisible();
  await expect(page.locator('#conv-loading')).toBeVisible();
  await expect(page.getByRole('button', { name: /nouvelle conversation/i })).toBeVisible();
});

// ─── happy path — liste chargée ────────────────────────────────────────────

test('happy path — conversations chargées : items et badges unread visibles', async ({ page }) => {
  await page.route('**/v1/conversations', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: 'conv-111',
          subject: 'Suivi traitement',
          last_message_at: '2026-06-01T10:00:00Z',
          unread_count: 2,
        },
        {
          id: 'conv-222',
          subject: 'Devis implant',
          last_message_at: '2026-05-30T08:30:00Z',
          unread_count: 0,
        },
      ]),
    }),
  );
  await page.goto('/patient/messages');

  const item1 = page.locator('[data-conversation-id="conv-111"]');
  await expect(item1).toBeVisible({ timeout: 5000 });
  await expect(item1).toContainText('Suivi traitement');
  await expect(item1.locator('.conv-badge')).toContainText('2');

  const item2 = page.locator('[data-conversation-id="conv-222"]');
  await expect(item2).toBeVisible();
  await expect(item2).toContainText('Devis implant');

  // Loading spinner gone
  await expect(page.locator('#conv-loading')).toBeHidden();
});

// ─── empty state ───────────────────────────────────────────────────────────

test('empty — liste vide affiche "Aucune conversation"', async ({ page }) => {
  await page.route('**/v1/conversations', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
  );
  await page.goto('/patient/messages');
  await expect(page.locator('#conv-empty')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#conv-empty')).toContainText(/aucune conversation/i);
});

// ─── error path — API 401 ─────────────────────────────────────────────────

test('error path — API 401 : message d\'erreur affiché', async ({ page }) => {
  await page.route('**/v1/conversations', (route) =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthenticated' }),
    }),
  );
  await page.goto('/patient/messages');
  await expect(page.locator('#conv-loading')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#conv-loading')).toContainText(/impossible/i);
  await expect(page.locator('#conv-list')).toBeHidden();
});
