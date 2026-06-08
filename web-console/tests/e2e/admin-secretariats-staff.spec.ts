import { test, expect } from '@playwright/test';

const TEST_ID = 'bbbb0000-0000-0000-0000-000000000001';
const PAGE_URL = `/admin/secretariats/${TEST_ID}/staff`;

// ── Render ─────────────────────────────────────────────────────────────────

test('render — /admin/secretariats/:id/staff affiche les trois sections', async ({ page }) => {
  await page.goto(PAGE_URL);
  await expect(page.getByRole('heading', { name: /Gestion du personnel/, level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Liste des membres/, level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Inviter \/ Créer secrétaire/, level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Retirer un secrétaire/, level: 2 })).toBeVisible();
});

// ── Happy path — GET /v1/cabinet/secretariats/:id affiche les membres ──────

test('happy path — GET 200 affiche la liste des membres dans #list-result', async ({ page }) => {
  await page.route(`**/v1/cabinet/secretariats/${TEST_ID}`, (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: TEST_ID,
        name: 'Secrétariat Test',
        members: [
          { user_id: 'user-0001', email: 'alice@cabinet.fr', role: 'secretary' },
          { user_id: 'user-0002', email: 'bob@cabinet.fr', role: 'manager' },
        ],
      }),
    });
  });

  await page.goto(PAGE_URL);
  const listSection = page.getByRole('region', { name: /Liste des membres/ });
  await listSection.getByLabel(/Access token/).fill('admin-token');
  await listSection.getByLabel(/ID du secrétariat/).fill(TEST_ID);
  await listSection.getByRole('button', { name: 'GET' }).click();

  await expect(page.locator('#list-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#list-result')).toContainText('alice@cabinet.fr');
  await expect(page.locator('#list-result')).toContainText('bob@cabinet.fr');
});

// ── Happy path — POST /v1/cabinet/secretariats/:id/staff crée un secrétaire ─

test('happy path — POST /staff 201 affiche le secrétaire créé dans #invite-result', async ({ page }) => {
  await page.route(`**/v1/cabinet/secretariats/${TEST_ID}/staff`, (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({
        user_id: 'user-0003',
        email: 'claire@cabinet.fr',
        role: 'secretary',
      }),
    });
  });

  await page.goto(PAGE_URL);
  const inviteSection = page.getByRole('region', { name: /Inviter \/ Créer secrétaire/ });
  await inviteSection.getByLabel(/Access token/).fill('admin-token');
  await inviteSection.getByLabel(/ID du secrétariat/).fill(TEST_ID);
  await inviteSection.getByLabel(/Email du secrétaire/).fill('claire@cabinet.fr');
  await inviteSection.getByRole('button', { name: 'POST staff' }).click();

  await expect(page.locator('#invite-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#invite-result')).toContainText('claire@cabinet.fr');
});

// ── Error path — POST 409 doublon affiché proprement ──────────────────────

test('error path — POST /staff 409 doublon affiche l\'erreur dans #invite-result', async ({ page }) => {
  await page.route(`**/v1/cabinet/secretariats/${TEST_ID}/staff`, (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 409,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'already_member' }),
    });
  });

  await page.goto(PAGE_URL);
  const inviteSection = page.getByRole('region', { name: /Inviter \/ Créer secrétaire/ });
  await inviteSection.getByLabel(/Access token/).fill('admin-token');
  await inviteSection.getByLabel(/ID du secrétariat/).fill(TEST_ID);
  await inviteSection.getByLabel(/Email du secrétaire/).fill('existing@cabinet.fr');
  await inviteSection.getByRole('button', { name: 'POST staff' }).click();

  await expect(page.locator('#invite-result')).toContainText('HTTP 409', { timeout: 5000 });
  await expect(page.locator('#invite-result')).toContainText('already_member');
});

// ── Error path — POST 403 non-autorisé affiché proprement ─────────────────

test('error path — POST /staff 403 non-autorisé affiche l\'erreur dans #invite-result', async ({ page }) => {
  await page.route(`**/v1/cabinet/secretariats/${TEST_ID}/staff`, (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto(PAGE_URL);
  const inviteSection = page.getByRole('region', { name: /Inviter \/ Créer secrétaire/ });
  await inviteSection.getByLabel(/Access token/).fill('non-manager-token');
  await inviteSection.getByLabel(/ID du secrétariat/).fill(TEST_ID);
  await inviteSection.getByLabel(/Email du secrétaire/).fill('test@cabinet.fr');
  await inviteSection.getByRole('button', { name: 'POST staff' }).click();

  await expect(page.locator('#invite-result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#invite-result')).toContainText('forbidden');
});

// ── Happy path — DELETE retirer un membre ─────────────────────────────────

test('happy path — DELETE /members/:user_id 204 affiche le résultat dans #remove-result', async ({ page }) => {
  const userId = 'user-0001';
  await page.route(`**/v1/cabinet/secretariats/${TEST_ID}/members/${userId}`, (route) => {
    if (route.request().method() !== 'DELETE') { route.continue(); return; }
    route.fulfill({ status: 204, body: '' });
  });

  await page.goto(PAGE_URL);
  const removeSection = page.getByRole('region', { name: /Retirer un secrétaire/ });
  await removeSection.getByLabel(/Access token/).fill('admin-token');
  await removeSection.getByLabel(/ID du secrétariat/).fill(TEST_ID);
  await removeSection.getByLabel(/user_id du secrétaire à retirer/).fill(userId);
  await removeSection.getByRole('button', { name: 'DELETE membre' }).click();

  await expect(page.locator('#remove-result')).toContainText('HTTP 204', { timeout: 5000 });
});
