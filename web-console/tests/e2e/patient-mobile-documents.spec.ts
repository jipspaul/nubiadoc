import { test, expect, type Page } from '@playwright/test';

const FAKE_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InBhdGllbnRAZXhhbXBsZS5jb20iLCJraWQiOiIxIiwia2luZCI6InBhdGllbnQifQ.signature';
const AUTH_COOKIE = `nubia_jwt=${FAKE_TOKEN}; nubia_role=patient`;

async function setupMobileTest(page: Page, documentsOverride?: unknown[]) {
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

  const documents = documentsOverride ?? [];
  await page.route('**/v1/documents**', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(documents) }),
  );
}

// ─── render: la page s'affiche avec le titre ──────────────────────────────────

test('render: la page affiche le titre Mes documents', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/documents', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByRole('heading', { name: /mes documents/i })).toBeVisible();
});

// ─── état vide: affiche le message quand aucun document ───────────────────────

test('état vide: affiche aucun document enregistré', async ({ page }) => {
  await setupMobileTest(page, []);
  await page.goto('/patient/m/documents', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByText('Aucun document enregistré.')).toBeVisible();
});

// ─── liste de documents: affiche les éléments de document ──────────────────────

test('liste de documents: affiche les éléments de document', async ({ page }) => {
  await setupMobileTest(page, [
    { id: 'doc-001', name: 'Radio panoramique', type: 'radiographie', created_at: '2026-06-01T10:00:00Z' },
    { id: 'doc-002', name: 'Compte-rendu', type: 'consultation', created_at: '2026-05-15T14:00:00Z' },
  ]);
  await page.goto('/patient/m/documents', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#docs-list')).toBeVisible();
  await expect(page.getByText('Radio panoramique')).toBeVisible();
  await expect(page.getByText('Compte-rendu')).toBeVisible();
});

// ─── élément de document: affiche le type et la date ──────────────────────────

test('élément de document: affiche le type et la date', async ({ page }) => {
  await setupMobileTest(page, [
    { id: 'doc-001', name: 'Radio panoramique', type: 'radiographie', created_at: '2026-06-01T10:00:00Z' },
  ]);
  await page.goto('/patient/m/documents', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByText('radiographie')).toBeVisible();
  await expect(page.locator('a[href="/patient/m/documents/doc-001"]')).toBeVisible();
});
