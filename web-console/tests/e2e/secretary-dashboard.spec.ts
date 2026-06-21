import { test, expect } from '@playwright/test';
import { secretaryUser } from './fixtures/users';

// ── Smoke happy path — login → dashboard ──────────────────────────────────────

function makeSecretaryJwt(): string {
  const payload = {
    email: secretaryUser.email,
    kind: 'pro',
    role: 'secretary',
    cabinet_id: secretaryUser.cabinet_id,
  };
  return `eyJhbGciOiJub25lIn0.${btoa(JSON.stringify(payload)).replace(/=/g, '')}.sig`;
}

test('smoke — login secrétaire avec creds fixture → tableau de bord chargé', async ({ page }) => {
  const jwt = makeSecretaryJwt();

  await page.route('**/v1/auth/login', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ access_token: jwt, refresh_token: 'r', token_type: 'Bearer', expires_in: 900 }),
    }),
  );
  await page.route('**/v1/cabinet/appointments**', route => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/cabinet/agenda**', route => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/cabinet/waiting-room', route => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });

  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill(secretaryUser.email);
  await page.locator('input[name="password"]').fill(secretaryUser.password);
  await page.locator('form#login-form button[type="submit"]').click();

  await page.waitForURL(/\/app/, { timeout: 5000 });

  await page.goto('/secretary/dashboard');
  await expect(page.getByRole('heading', { name: 'Tableau de bord secrétaire', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Rendez-vous du jour/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Créneaux du jour/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /File d'attente/i })).toBeVisible();
});

test('render — /secretary/dashboard affiche le titre et les trois sections', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.goto('/secretary/dashboard');
  await expect(page.getByRole('heading', { name: 'Tableau de bord secrétaire', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Rendez-vous du jour/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Créneaux du jour/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /File d'attente/i })).toBeVisible();
  await expect(page.getByRole('table', { name: 'Liste des rendez-vous du jour' })).toBeVisible();
  await expect(page.getByRole('table', { name: 'Créneaux du jour' })).toBeVisible();
  await expect(page.getByRole('list', { name: 'Patients en salle d\'attente' })).toBeVisible();
});

test('happy path — affiche les rendez-vous du jour retournés par l\'API', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  const todayIso = new Date().toISOString().slice(0, 10);
  await page.route('**/v1/cabinet/appointments**', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: '00000000-0000-0000-0000-000000000001',
          patient_id: 'pat-001',
          scheduled_at: `${todayIso}T09:00:00.000Z`,
          status: 'confirmed',
        },
      ]),
    });
  });
  await page.route('**/v1/cabinet/agenda**', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/cabinet/waiting-room', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.goto('/secretary/dashboard');
  await expect(page.locator('#appointments-tbody')).toContainText('pat-001', { timeout: 5000 });
  await expect(page.locator('#appointments-tbody')).toContainText('confirmed');
});

test('error path — affiche erreur 403 sur la section rendez-vous si l\'API refuse l\'accès', async ({ page }) => {
  await page.context().addCookies([
    { name: 'nubia_jwt', value: 'test-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'secretary', domain: 'localhost', path: '/' },
  ]);
  await page.route('**/v1/cabinet/appointments**', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });
  await page.route('**/v1/cabinet/agenda**', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.route('**/v1/cabinet/waiting-room', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
  });
  await page.goto('/secretary/dashboard');
  await expect(page.locator('#appointments-status')).toContainText('403', { timeout: 5000 });
});
