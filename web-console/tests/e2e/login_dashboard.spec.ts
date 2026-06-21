import { test, expect } from '@playwright/test';

const FIXTURE_EMAIL = 'secretaire@fixture.nubia.test';
const FIXTURE_PASSWORD = 'MotDePasse123!';

/**
 * JWT minimal secrétaire — header + payload base64url + sig factice.
 * session.ts#decodePayload extrait le payload pour poser nubia_role et nubia_ctx.
 */
function makeSecretaryJwt(): string {
  const header = Buffer.from('{"alg":"HS256","typ":"JWT"}')
    .toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const payload = Buffer.from(JSON.stringify({
    email: FIXTURE_EMAIL,
    kind: 'pro',
    role: 'secretary',
    cabinet_id: 'cab-fixture',
    secretariat_id: 'sec-fixture',
  })).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${header}.${payload}.sig`;
}

test('smoke — login secrétariat puis dashboard chargé (happy path)', async ({ page }) => {
  const jwt = makeSecretaryJwt();

  // Intercept POST /v1/auth/login → 200 avec le JWT fixture secrétaire
  await page.route('**/v1/auth/login', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        access_token: jwt,
        refresh_token: 'refresh-fixture',
        token_type: 'Bearer',
        expires_in: 900,
      }),
    }),
  );

  // Login
  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill(FIXTURE_EMAIL);
  await page.locator('input[name="password"]').fill(FIXTURE_PASSWORD);
  await page.locator('form#login-form button[type="submit"]').click();

  // Attend la redirection post-login (login() pose nubia_jwt / nubia_role / nubia_ctx)
  await page.waitForURL((url) => !url.pathname.includes('/auth/login'), { timeout: 5000 });

  // Mocke les API du dashboard avant navigation
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

  // Navigue vers le dashboard secrétaire (nubia_ctx pose par login() donne l'accès direct)
  await page.goto('/secretary/dashboard');

  // Asserte que le dashboard est chargé
  await expect(page.getByRole('heading', { name: 'Tableau de bord secrétaire', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Rendez-vous du jour/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /File d'attente/i })).toBeVisible();
});
