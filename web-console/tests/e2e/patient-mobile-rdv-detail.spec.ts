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

test('render: la page affiche le titre Détail du rendez-vous', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/rdv/appt-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByRole('heading', { name: /détail du rendez-vous/i })).toBeVisible();
});

// ─── lien retour: navigue vers la liste des RDV ──────────────────────────────

test('lien retour: affiche le lien vers la liste des RDV', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/rdv/appt-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByRole('link', { name: /← Mes rendez-vous/i })).toBeVisible();
});

// ─── structure: affiche la carte de détails ──────────────────────────────────

test('structure: affiche la carte de détails', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/rdv/appt-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#rdv-card')).toBeAttached();
  await expect(page.locator('#rdv-date')).toBeAttached();
  await expect(page.locator('#rdv-provider')).toBeAttached();
  await expect(page.locator('#rdv-status-badge')).toBeAttached();
});

// ─── structure: affiche la zone de chargement ────────────────────────────────

test('structure: affiche la zone de chargement', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/rdv/appt-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#rdv-loading')).toBeAttached();
});

// ─── structure: affiche la section des actions ───────────────────────────────

test('structure: affiche la section des actions', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/rdv/appt-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#actions-section')).toBeAttached();
});

// ─── structure: affiche le message d\'erreur ─────────────────────────────────

test('structure: affiche le message d\'erreur', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/rdv/appt-001', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#rdv-error')).toBeAttached();
});
