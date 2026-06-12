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

async function loadMobilePage(page: Page) {
  await setupMobileTest(page);
  await page.goto('/patient/m/rdv', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');
}

// ─── bottom nav visible sur viewport mobile ─────────────────────────────────

test('bottom nav visible sur viewport mobile', async ({ page }) => {
  await loadMobilePage(page);
  await page.setViewportSize({ width: 375, height: 812 });

  const nav = page.locator('nav.m-tabbar');
  await expect(nav).toBeVisible();

  const box = await nav.boundingBox();
  expect(box).not.toBeNull();
  expect(box!.y).toBeGreaterThanOrEqual(0);
  expect(box!.y + box!.height).toBeLessThanOrEqual(812);
});

// ─── header minimal sur viewport mobile ─────────────────────────────────────

test('header minimal sur viewport mobile', async ({ page }) => {
  await loadMobilePage(page);
  await page.setViewportSize({ width: 375, height: 812 });

  const header = page.locator('header.m-header');
  await expect(header).toBeVisible();

  const logo = header.locator('a.m-logo');
  await expect(logo).toBeVisible();
  await expect(logo).toHaveText('Nubia');

  const headerBox = await header.boundingBox();
  expect(headerBox).not.toBeNull();
  expect(headerBox!.width).toBeLessThanOrEqual(375);
});

// ─── contenu scrollable sans overflow ───────────────────────────────────────

test('contenu scrollable sans overflow', async ({ page }) => {
  await loadMobilePage(page);
  await page.setViewportSize({ width: 375, height: 812 });

  const main = page.locator('main.m-main');
  await expect(main).toBeVisible();

  const overflows = await main.evaluate((el) => {
    return {
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
    };
  });
  expect(overflows.scrollWidth).toBeLessThanOrEqual(overflows.clientWidth + 1);
});
