import { test, expect, type Page, type BrowserContext } from '@playwright/test';

const FAKE_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InBhdGllbnRAZXhhbXBsZS5jb20iLCJraWQiOiIxIiwia2luZCI6InBhdGllbnQifQ.signature';
const AUTH_COOKIE = `nubia_jwt=${FAKE_TOKEN}; nubia_role=patient`;

const MOBILE_ROUTES = {
  accueil: '/patient/m/accueil',
  rdv: '/patient/m/rdv',
  documents: '/patient/m/documents',
  messages: '/patient/m/messages',
  profil: '/patient/m/profil',
} as const;

const TAB_LABELS = ['Accueil', 'RDV', 'Documents', 'Messages', 'Profil'] as const;

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

  await page.route('**/v1/appointments**', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
  );
  await page.route('**/v1/documents**', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
  );
  await page.route('**/v1/conversations**', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
  );
  await page.route('**/v1/account', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'acc-001',
        email: 'patient@example.com',
        first_name: 'Jean',
        last_name: 'Dupont',
      }),
    }),
  );
}

// ─── bottom nav affiche les 5 onglets ────────────────────────────────────────

test('bottom nav affiche les 5 onglets', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto(MOBILE_ROUTES.rdv, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  const nav = page.locator('nav.m-tabbar');
  await expect(nav).toBeVisible();

  const tabs = nav.locator('a.m-tab');
  await expect(tabs).toHaveCount(5);

  for (const label of TAB_LABELS) {
    await expect(nav.getByText(label, { exact: true })).toBeVisible();
  }
});

// ─── navigation vers RDV ─────────────────────────────────────────────────────

test('navigation vers RDV', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto(MOBILE_ROUTES.documents, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await page.locator('nav.m-tabbar').getByText('RDV', { exact: true }).click();

  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.rdv));
  await expect(page.getByRole('heading', { name: /mes rendez-vous/i })).toBeVisible();
});

// ─── navigation vers Documents ────────────────────────────────────────────────

test('navigation vers Documents', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto(MOBILE_ROUTES.rdv, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await page.locator('nav.m-tabbar').getByText('Documents', { exact: true }).click();

  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.documents));
  await expect(page.getByRole('heading', { name: /mes documents/i })).toBeVisible();
});

// ─── navigation vers Messages ────────────────────────────────────────────────

test('navigation vers Messages', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto(MOBILE_ROUTES.rdv, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await page.locator('nav.m-tabbar').getByText('Messages', { exact: true }).click();

  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.messages));
  await expect(page.getByRole('heading', { name: /mes messages/i })).toBeVisible();
});

// ─── navigation vers Profil ──────────────────────────────────────────────────

test('navigation vers Profil', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto(MOBILE_ROUTES.rdv, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await page.locator('nav.m-tabbar').getByText('Profil', { exact: true }).click();

  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.profil));
  await expect(page.getByRole('heading', { name: /mon profil/i })).toBeVisible();
});

// ─── onglet actif mis en surbrillance ────────────────────────────────────────

test('onglet actif mis en surbrillance', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto(MOBILE_ROUTES.rdv, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  const nav = page.locator('nav.m-tabbar');

  const rdvTab = nav.locator('a.m-tab', { hasText: 'RDV' });
  await expect(rdvTab).toHaveClass(/active/);

  await nav.getByText('Documents', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.documents));

  const docsTab = nav.locator('a.m-tab', { hasText: 'Documents' });
  await expect(docsTab).toHaveClass(/active/);
  await expect(rdvTab).not.toHaveClass(/active/);

  await nav.getByText('Messages', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.messages));

  const msgsTab = nav.locator('a.m-tab', { hasText: 'Messages' });
  await expect(msgsTab).toHaveClass(/active/);
  await expect(docsTab).not.toHaveClass(/active/);
});
