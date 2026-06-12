import { test, expect, type Page } from '@playwright/test';

const FAKE_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InBhdGllbnRAZXhhbXBsZS5jb20iLCJraWQiOiIxIiwia2luZCI6InBhdGllbnQifQ.signature';
const AUTH_COOKIE = `nubia_jwt=${FAKE_TOKEN}; nubia_role=patient`;

const MOBILE_ROUTES = {
  accueil: '/patient/m/accueil',
  rdv: '/patient/m/rdv',
  documents: '/patient/m/documents',
  messages: '/patient/m/messages',
  profil: '/patient/m/profil',
} as const;

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

  await page.route('**/v1/dashboard**', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        next_appointment: null,
        unread_messages: 0,
        pending_quotes: 0,
        to_sign: [],
        to_pay: [],
      }),
    }),
  );
  await page.route('**/v1/appointments**', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
  );
  await page.route('**/v1/documents**', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
  );
  await page.route('**/v1/conversations**', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
  );
  await page.route('**/v1/account**', (route) =>
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

// ─── flux complet: rdv → messages → profil → documents → rdv ──────────────────

test('flux complet: rdv → messages → profil → documents → rdv', async ({ page }) => {
  await setupMobileTest(page);

  // RDV
  await page.goto(MOBILE_ROUTES.rdv, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');
  await expect(page.getByRole('heading', { name: /mes rendez-vous/i })).toBeVisible();

  // Messages
  await page.locator('nav.m-tabbar').getByText('Messages', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.messages));
  await expect(page.getByRole('heading', { name: /mes messages/i })).toBeVisible();

  // Profil
  await page.locator('nav.m-tabbar').getByText('Profil', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.profil));
  await expect(page.getByRole('heading', { name: /mon profil/i })).toBeVisible();

  // Documents
  await page.locator('nav.m-tabbar').getByText('Documents', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.documents));
  await expect(page.getByRole('heading', { name: /mes documents/i })).toBeVisible();

  // Retour à RDV
  await page.locator('nav.m-tabbar').getByText('RDV', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.rdv));
  await expect(page.getByRole('heading', { name: /mes rendez-vous/i })).toBeVisible();
});

// ─── persistance de l'état: l'état persiste entre les changements d'onglet ────

test('persistance de l\'état: l\'état persiste entre les changements d\'onglet', async ({ page }) => {
  await setupMobileTest(page);

  // Aller à RDV
  await page.goto(MOBILE_ROUTES.rdv, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');
  await expect(page.getByRole('heading', { name: /mes rendez-vous/i })).toBeVisible();

  // Aller à Documents
  await page.locator('nav.m-tabbar').getByText('Documents', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.documents));
  await expect(page.getByRole('heading', { name: /mes documents/i })).toBeVisible();

  // Retour à RDV
  await page.locator('nav.m-tabbar').getByText('RDV', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.rdv));
  await expect(page.getByRole('heading', { name: /mes rendez-vous/i })).toBeVisible();

  // Aller à Messages
  await page.locator('nav.m-tabbar').getByText('Messages', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.messages));
  await expect(page.getByRole('heading', { name: /mes messages/i })).toBeVisible();

  // Retour à RDV
  await page.locator('nav.m-tabbar').getByText('RDV', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.rdv));
  await expect(page.getByRole('heading', { name: /mes rendez-vous/i })).toBeVisible();
});

// ─── onglet actif: l\'onglet actif change à la navigation ─────────────────────

test('onglet actif: l\'onglet actif change à la navigation', async ({ page }) => {
  await setupMobileTest(page);

  await page.goto(MOBILE_ROUTES.rdv, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  const rdvTab = page.locator('nav.m-tabbar a.m-tab', { hasText: 'RDV' });
  await expect(rdvTab).toHaveClass(/active/);

  await page.locator('nav.m-tabbar').getByText('Documents', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(MOBILE_ROUTES.documents));

  const docsTab = page.locator('nav.m-tabbar a.m-tab', { hasText: 'Documents' });
  await expect(docsTab).toHaveClass(/active/);
  await expect(rdvTab).not.toHaveClass(/active/);
});
