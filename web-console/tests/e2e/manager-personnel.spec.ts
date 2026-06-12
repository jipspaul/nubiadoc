import { test, expect } from '@playwright/test';

const PAGE_URL = '/manager/personnel';
const SEC_ID = 'bbbb0000-0000-0000-0000-000000000002';

function adminCookies() {
  return [
    { name: 'nubia_jwt', value: 'admin-token', domain: 'localhost', path: '/' },
    { name: 'nubia_role', value: 'admin', domain: 'localhost', path: '/' },
  ];
}

// ── Auth guard ──────────────────────────────────────────────────────────────

test('auth guard — sans cookie nubia_jwt redirige vers /auth/login', async ({ page }) => {
  await page.goto(PAGE_URL);
  await expect(page).toHaveURL(/\/auth\/login/);
});

// ── Render ──────────────────────────────────────────────────────────────────

test('render — /manager/personnel affiche le titre et les sections', async ({ page }) => {
  await page.context().addCookies(adminCookies());
  await page.goto(PAGE_URL);
  await expect(page.getByRole('heading', { name: /Gestion du personnel/, level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Secrétariat/, level: 2 })).toBeVisible();
  await expect(page.getByLabel(/ID du secrétariat/)).toBeVisible();
  await expect(page.getByRole('button', { name: /Charger le personnel/ })).toBeVisible();
});

// ── Happy path — GET staff 200 ──────────────────────────────────────────────

test('happy path — GET staff 200 affiche les membres dans le tableau', async ({ page }) => {
  await page.context().addCookies(adminCookies());
  await page.route(`**/v1/cabinet/secretariats/${SEC_ID}/staff`, (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { user_id: 'user-0001', email: 'alice@cabinet.fr', role: 'secretary' },
        { user_id: 'user-0002', email: 'bob@cabinet.fr', role: 'manager' },
      ]),
    });
  });

  await page.goto(PAGE_URL);
  await page.getByLabel(/ID du secrétariat/).fill(SEC_ID);
  await page.getByRole('button', { name: /Charger le personnel/ }).click();

  await expect(page.locator('#section-staff')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#staff-tbody')).toContainText('alice@cabinet.fr');
  await expect(page.locator('#staff-tbody')).toContainText('bob@cabinet.fr');
});

// ── Happy path — GET staff 200 liste vide ───────────────────────────────────

test('happy path — GET staff 200 liste vide affiche le message vide', async ({ page }) => {
  await page.context().addCookies(adminCookies());
  await page.route(`**/v1/cabinet/secretariats/${SEC_ID}/staff`, (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([]),
    });
  });

  await page.goto(PAGE_URL);
  await page.getByLabel(/ID du secrétariat/).fill(SEC_ID);
  await page.getByRole('button', { name: /Charger le personnel/ }).click();

  await expect(page.locator('#staff-empty')).toBeVisible({ timeout: 5000 });
});

// ── Error path — GET staff 403 ──────────────────────────────────────────────

test('error path — GET staff 403 affiche le message d\'erreur dans #staff-status', async ({ page }) => {
  await page.context().addCookies(adminCookies());
  await page.route(`**/v1/cabinet/secretariats/${SEC_ID}/staff`, (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({ status: 403, contentType: 'application/json', body: JSON.stringify({ code: 'forbidden' }) });
  });

  await page.goto(PAGE_URL);
  await page.getByLabel(/ID du secrétariat/).fill(SEC_ID);
  await page.getByRole('button', { name: /Charger le personnel/ }).click();

  await expect(page.locator('#staff-status')).toContainText('403', { timeout: 5000 });
});

// ── Happy path — POST staff 201 ─────────────────────────────────────────────

test('happy path — POST staff 201 ajoute le membre dans le tableau', async ({ page }) => {
  await page.context().addCookies(adminCookies());

  await page.route(`**/v1/cabinet/secretariats/${SEC_ID}/staff`, (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
      return;
    }
    if (route.request().method() === 'POST') {
      route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({ user_id: 'user-0003', email: 'claire@cabinet.fr', role: 'secretary' }),
      });
      return;
    }
    route.continue();
  });

  await page.goto(PAGE_URL);

  // Load staff first to reveal the add section
  await page.getByLabel(/ID du secrétariat/).fill(SEC_ID);
  await page.getByRole('button', { name: /Charger le personnel/ }).click();
  await expect(page.locator('#section-add')).toBeVisible({ timeout: 5000 });

  await page.getByLabel(/Adresse e-mail/).fill('claire@cabinet.fr');
  await page.getByRole('button', { name: /Ajouter/ }).click();

  await expect(page.locator('#add-status')).toContainText('succès', { timeout: 5000 });
  await expect(page.locator('#staff-tbody')).toContainText('claire@cabinet.fr');
});

// ── Error path — POST staff 409 ─────────────────────────────────────────────

test('error path — POST staff 409 affiche le message doublon dans #add-status', async ({ page }) => {
  await page.context().addCookies(adminCookies());

  await page.route(`**/v1/cabinet/secretariats/${SEC_ID}/staff`, (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
      return;
    }
    if (route.request().method() === 'POST') {
      route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ code: 'already_member' }) });
      return;
    }
    route.continue();
  });

  await page.goto(PAGE_URL);
  await page.getByLabel(/ID du secrétariat/).fill(SEC_ID);
  await page.getByRole('button', { name: /Charger le personnel/ }).click();
  await expect(page.locator('#section-add')).toBeVisible({ timeout: 5000 });

  await page.getByLabel(/Adresse e-mail/).fill('existing@cabinet.fr');
  await page.getByRole('button', { name: /Ajouter/ }).click();

  await expect(page.locator('#add-status')).toContainText('déjà membre', { timeout: 5000 });
});
