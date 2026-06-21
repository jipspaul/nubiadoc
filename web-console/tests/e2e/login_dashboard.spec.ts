import { test, expect } from '@playwright/test';

const SEED_EMAIL    = process.env.SEED_SECRETARY_EMAIL    ?? 'secretaire.demo@nubia.test';
const SEED_PASSWORD = process.env.SEED_SECRETARY_PASSWORD ?? 'NubiaDemo1!';

/**
 * Construit un faux JWT (signature ignorée par le client) dont le payload est
 * décodable par `decodePayload` de session.ts.  Les tests E2E mocquent l'API,
 * aucune vérification de signature n'a lieu côté navigateur.
 */
function makeFakeJwt(payload: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const body   = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.fake`;
}

const ACCESS_TOKEN = makeFakeJwt({
  email: SEED_EMAIL,
  kind: 'pro',
  role: 'secretary',
  cabinet_id: 'cab-001',
  secretariat_id: 'sec-001',
  exp: 9999999999,
});

test('smoke — login secrétariat + redirection dashboard affiche le tableau de bord', async ({ page }) => {
  // Mock POST /v1/auth/login → succès sans sélection de contexte
  await page.route('**/v1/auth/login', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        access_token: ACCESS_TOKEN,
        refresh_token: 'fake-refresh',
        token_type: 'Bearer',
        expires_in: 3600,
        context_required: false,
      }),
    });
  });

  // Stubs des trois appels API que /secretary/dashboard déclenche
  await page.route('**/v1/cabinet/appointments**', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/cabinet/agenda**', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/cabinet/waiting-room', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });

  // Flow : login form → soumission → redirection vers /secretary/dashboard
  await page.goto('/auth/login');
  await page.fill('input[name="email"]', SEED_EMAIL);
  await page.fill('input[name="password"]', SEED_PASSWORD);
  await page.click('button[type="submit"]');

  // Le middleware redirige /app → /secretary/dashboard (rôle secretary + ctx présent)
  await page.waitForURL('**/secretary/dashboard', { timeout: 10_000 });
  await expect(page.getByRole('heading', { name: 'Tableau de bord secrétaire', level: 1 })).toBeVisible();
});
