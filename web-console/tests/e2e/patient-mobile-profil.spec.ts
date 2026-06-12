import { test, expect, type Page } from '@playwright/test';

const FAKE_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InBhdGllbnRAZXhhbXBsZS5jb20iLCJraWQiOiIxIiwia2luZCI6InBhdGllbnQifQ.signature';
const AUTH_COOKIE = `nubia_jwt=${FAKE_TOKEN}; nubia_role=patient`;

const MOCK_ACCOUNT = {
  id: 'acc-001',
  email: 'patient@example.com',
  first_name: 'Jean',
  last_name: 'Dupont',
  phone: '+33612345678',
  birth_date: '1990-01-15',
};

async function setupMobileTest(page: Page, accountOverride?: Record<string, unknown>) {
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

  await page.route('**/v1/account**', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ ...MOCK_ACCOUNT, ...accountOverride }),
    }),
  );
}

// ─── render: la page s'affiche avec le titre ──────────────────────────────────

test('render: la page affiche le titre Mon profil', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/profil', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByRole('heading', { name: /mon profil/i })).toBeVisible();
  await expect(page.getByText('Informations du compte')).toBeVisible();
});

// ─── infos utilisateur: affiche le nom et l'email ────────────────────────────

test('infos utilisateur: affiche le nom et l\'email', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/profil', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('input[name="first_name"]')).toHaveValue('Jean');
  await expect(page.locator('input[name="last_name"]')).toHaveValue('Dupont');
  await expect(page.locator('input[name="email"]')).toHaveValue('patient@example.com');
});

// ─── liens de navigation: affiche les liens vers les sous-pages ───────────────

test('liens de navigation: affiche les liens vers les sous-pages', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/profil', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('.m-subnav a[href="/patient/m/profil"]')).toBeVisible();
  await expect(page.locator('.m-subnav a[href="/patient/m/profil/couverture"]')).toBeVisible();
  await expect(page.locator('.m-subnav a[href="/patient/m/profil/proches"]')).toBeVisible();
  await expect(page.locator('.m-subnav a[href="/patient/m/profil/consentements"]')).toBeVisible();
  await expect(page.locator('.m-subnav a[href="/patient/m/profil/notifications"]')).toBeVisible();
});

// ─── lien actif: la page courante est marquée comme active ────────────────────

test('lien actif: la page courante est marquée comme active', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/profil', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  const currentLink = page.locator('.m-subnav a[aria-current="page"]');
  await expect(currentLink).toBeVisible();
  await expect(currentLink).toHaveAttribute('href', '/patient/m/profil');
});

// ─── téléphone: affiche le numéro de téléphone ───────────────────────────────

test('téléphone: affiche le numéro de téléphone', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/profil', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('input[name="phone"]')).toHaveValue('+33612345678');
});
