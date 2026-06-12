import { test, expect, type Page } from '@playwright/test';

const FAKE_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InBhdGllbnRAZXhhbXBsZS5jb20iLCJraWQiOiIxIiwia2luZCI6InBhdGllbnQifQ.signature';
const AUTH_COOKIE = `nubia_jwt=${FAKE_TOKEN}; nubia_role=patient`;

async function setupMobileTest(page: Page, conversationsOverride?: unknown[]) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Fetch.enable', {
    patterns: [{ urlPattern: '*localhost:4321*', requestStage: 'Request' }],
  });
  cdp.on('Fetch.requestPaused', async (params) => {
    try {
      const headers = params.request.headers;
      headers['cookie'] = AUTH_COOKIE;
      await cdp.send('Fetch.continueRequest', {
        requestId: params.requestId,
        headers: Object.entries(headers).map(([n, v]) => ({ name: n, value: v })),
      });
    } catch {
      // CDP session may close during navigation
    }
  });

  await page.addInitScript((token: string) => {
    localStorage.setItem('nubia_jwt', token);
  }, FAKE_TOKEN);

  const conversations = conversationsOverride ?? [];
  await page.route('**/v1/conversations**', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(conversations) }),
  );
}

// ─── render: la page s'affiche avec le titre ──────────────────────────────────

test('render: la page affiche le titre Mes messages', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/messages', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByRole('heading', { name: /mes messages/i })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Nouvelle conversation' })).toBeVisible();
});

// ─── état vide: affiche le message quand aucune conversation ──────────────────

test('état vide: affiche aucune conversation', async ({ page }) => {
  await setupMobileTest(page, []);
  await page.goto('/patient/m/messages', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByText('Aucune conversation.')).toBeVisible();
});

// ─── liste de conversations: affiche les éléments de conversation ─────────────

test('liste de conversations: affiche les éléments de conversation', async ({ page }) => {
  await setupMobileTest(page, [
    { id: 'conv-001', subject: 'Question sur mon traitement', unread_count: 2, last_message_at: '2026-06-10T14:00:00Z' },
    { id: 'conv-002', subject: 'Résultats d\'examens', unread_count: 0, last_message_at: '2026-06-08T10:00:00Z' },
  ]);
  await page.goto('/patient/m/messages', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#conv-list')).toBeVisible();
  await expect(page.getByText('Question sur mon traitement')).toBeVisible();
  await expect(page.getByText('Résultats d\'examens')).toBeVisible();
});

// ─── élément de conversation: affiche le badge de non-lus ─────────────────────

test('élément de conversation: affiche le badge de non-lus', async ({ page }) => {
  await setupMobileTest(page, [
    { id: 'conv-001', subject: 'Question sur mon traitement', unread_count: 2, last_message_at: '2026-06-10T14:00:00Z' },
  ]);
  await page.goto('/patient/m/messages', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  const badge = page.locator('#conv-list .mobile-conv-badge').first();
  await expect(badge).toContainText('2');
});

// ─── élément de conversation: affiche le lien vers le fil ─────────────────────

test('élément de conversation: affiche le lien vers le fil', async ({ page }) => {
  await setupMobileTest(page, [
    { id: 'conv-001', subject: 'Question sur mon traitement', unread_count: 0, last_message_at: '2026-06-10T14:00:00Z' },
  ]);
  await page.goto('/patient/m/messages', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#conv-list a[href="/patient/m/messages/conv-001"]')).toBeVisible();
});
