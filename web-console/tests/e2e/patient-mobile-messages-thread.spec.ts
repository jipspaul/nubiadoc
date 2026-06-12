import { test, expect, type Page } from '@playwright/test';

const FAKE_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InBhdGllbnRAZXhhbXBsZS5jb20iLCJraWQiOiIxIiwia2luZCI6InBhdGllbnQifQ.signature';
const AUTH_COOKIE = `nubia_jwt=${FAKE_TOKEN}; nubia_role=patient`;

async function setupMobileTest(page: Page) {
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
}

// ─── render: la page s'affiche avec le titre ──────────────────────────────────

test('render: la page affiche le titre Conversation', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/messages/conv-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByRole('heading', { name: /conversation/i })).toBeVisible();
});

// ─── lien retour: navigue vers la liste des messages ──────────────────────────

test('lien retour: affiche le lien vers la liste des messages', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/messages/conv-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByRole('link', { name: /← Mes messages/i })).toBeVisible();
});

// ─── structure: affiche le formulaire de réponse ─────────────────────────────

test('structure: affiche le formulaire de réponse', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/messages/conv-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#reply-form')).toBeVisible();
  await expect(page.locator('#reply-body')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

// ─── structure: affiche la zone de chargement des messages ────────────────────

test('structure: affiche la zone de chargement des messages', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/messages/conv-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#msg-loading')).toBeVisible();
});

// ─── structure: affiche le conteneur de messages ─────────────────────────────

test('structure: affiche le conteneur de messages', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/messages/conv-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  const msgList = page.locator('#msg-list');
  const msgEmpty = page.locator('#msg-empty');
  const isMsgListPresent = await msgList.count() > 0;
  const isMsgEmptyPresent = await msgEmpty.count() > 0;
  expect(isMsgListPresent || isMsgEmptyPresent).toBeTruthy();
});
