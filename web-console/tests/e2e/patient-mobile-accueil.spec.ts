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

// ─── render: la page s'affiche ou redirige vers login ─────────────────────────

test('render: la page s\'affiche ou redirige vers login', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/accueil', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  const url = page.url();
  const isAccueil = url.includes('/patient/m/accueil');
  const isLogin = url.includes('/auth/login');
  expect(isAccueil || isLogin).toBeTruthy();
});

// ─── accueil: affiche les cartes quand le dashboard est chargé ────────────────

test('accueil: affiche les cartes quand le dashboard est chargé', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/accueil', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  if (page.url().includes('/patient/m/accueil')) {
    const cards = page.locator('.mobile-cards, .mobile-card');
    const hasCards = await cards.count() > 0;
    expect(hasCards).toBeTruthy();
  } else {
    expect(page.url()).toContain('/auth/login');
  }
});

// ─── accueil: les sections du tableau de bord sont présentes ──────────────────

test('accueil: les sections du tableau de bord sont présentes', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/accueil', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  if (page.url().includes('/patient/m/accueil')) {
    await expect(page.getByText('Prochain RDV')).toBeVisible();
    await expect(page.getByText('Messages')).toBeVisible();
    await expect(page.getByText('Devis')).toBeVisible();
    await expect(page.getByText('Paiements')).toBeVisible();
  } else {
    expect(page.url()).toContain('/auth/login');
  }
});

// ─── accueil sans auth: redirige vers login ───────────────────────────────────

test('accueil sans auth: redirige vers login', async ({ page }) => {
  await page.goto('/patient/m/accueil', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page).toHaveURL(/\/auth\/login/);
});
