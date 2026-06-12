import { test, expect, type Page } from '@playwright/test';

const FAKE_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InBhdGllbnRAZXhhbXBsZS5jb20iLCJraWQiOiIxIiwia2luZCI6InBhdGllbnQifQ.signature';
const AUTH_COOKIE = `nubia_jwt=${FAKE_TOKEN}; nubia_role=patient`;

async function setupMobileTest(page: Page, opts?: { upcoming?: unknown[]; past?: unknown[] }) {
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

  const upcoming = opts?.upcoming ?? [];
  const past = opts?.past ?? [];

  await page.route('**/v1/appointments**', (route) => {
    const url = route.request().url();
    if (url.includes('status=past')) {
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(past) });
    } else {
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(upcoming) });
    }
  });
}

// ─── render: la page s'affiche avec le titre ──────────────────────────────────

test('render: la page affiche le titre Mes rendez-vous', async ({ page }) => {
  await setupMobileTest(page);
  await page.goto('/patient/m/rdv', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByRole('heading', { name: /mes rendez-vous/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'À venir' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Historique' })).toBeVisible();
});

// ─── état vide: affiche le message quand aucun rendez-vous ────────────────────

test('état vide: affiche aucun rendez-vous à venir', async ({ page }) => {
  await setupMobileTest(page, { upcoming: [], past: [] });
  await page.goto('/patient/m/rdv', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByText('Aucun rendez-vous à venir.')).toBeVisible();
  await expect(page.getByText('Aucun rendez-vous passé.')).toBeVisible();
});

// ─── liste de rendez-vous: affiche les sections à venir et historique ──────────

test('liste de rendez-vous: affiche les sections à venir et historique', async ({ page }) => {
  await setupMobileTest(page, {
    upcoming: [
      { id: 'appt-001', status: 'confirmed', scheduled_at: '2026-06-20T10:00:00Z', provider_id: 'prov-001', provider: { display_name: 'Dr. Martin' } },
    ],
    past: [
      { id: 'appt-002', status: 'completed', scheduled_at: '2026-06-01T14:00:00Z', provider_id: 'prov-001', provider: { display_name: 'Dr. Martin' } },
    ],
  });
  await page.goto('/patient/m/rdv', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.locator('#upcoming-list')).toBeVisible();
  await expect(page.locator('#past-list')).toBeVisible();
});

// ─── élément de rendez-vous: affiche la date et le praticien ──────────────────

test('élément de rendez-vous: affiche la date et le praticien', async ({ page }) => {
  await setupMobileTest(page, {
    upcoming: [
      { id: 'appt-001', status: 'confirmed', scheduled_at: '2026-06-20T10:00:00Z', provider_id: 'prov-001', provider: { display_name: 'Dr. Martin' } },
    ],
  });
  await page.goto('/patient/m/rdv', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  await expect(page.getByText('Dr. Martin')).toBeVisible();
  await expect(page.locator('#upcoming-list a[href="/patient/m/rdv/appt-001"]')).toBeVisible();
});

// ─── élément de rendez-vous: affiche le badge de statut ───────────────────────

test('élément de rendez-vous: affiche le badge de statut', async ({ page }) => {
  await setupMobileTest(page, {
    upcoming: [
      { id: 'appt-001', status: 'confirmed', scheduled_at: '2026-06-20T10:00:00Z', provider_id: 'prov-001', provider: { display_name: 'Dr. Martin' } },
    ],
  });
  await page.goto('/patient/m/rdv', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');

  const badge = page.locator('#upcoming-list .mobile-rdv-badge[data-status="confirmed"]');
  await expect(badge).toBeVisible();
  await expect(badge).toContainText('confirmed');
});
