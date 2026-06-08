import { test, expect } from '@playwright/test';

// ── Render ─────────────────────────────────────────────────────────────────

test('render — /admin/secretariats affiche le titre et toutes les sections CRUD', async ({ page }) => {
  await page.goto('/admin/secretariats');
  await expect(page.getByRole('heading', { name: /Secrétariats/, level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Lister les secrétariats/, level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Créer un secrétariat/, level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Modifier un secrétariat/, level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Supprimer un secrétariat/, level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Ajouter un membre/, level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Retirer un membre/, level: 2 })).toBeVisible();
});

// ── Happy path — GET /v1/cabinet/secretariats ──────────────────────────────

test('happy path — GET /v1/cabinet/secretariats 200 affiche la liste dans #list-result', async ({ page }) => {
  await page.route('**/v1/cabinet/secretariats', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 'aaaa0000-0000-0000-0000-000000000001', name: 'Secrétariat Nord' },
        { id: 'aaaa0000-0000-0000-0000-000000000002', name: 'Secrétariat Sud' },
      ]),
    });
  });

  await page.goto('/admin/secretariats');
  // The list form is the first form — fill its access_token input and submit
  const listSection = page.getByRole('region', { name: /Lister les secrétariats/ });
  await listSection.getByLabel(/Access token/).fill('admin-bearer-token');
  await listSection.getByRole('button', { name: 'GET' }).click();
  await expect(page.locator('#list-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#list-result')).toContainText('Secrétariat Nord');
  await expect(page.locator('#list-result')).toContainText('Secrétariat Sud');
});

// ── Error path — GET 403 ────────────────────────────────────────────────────

test('error path — GET /v1/cabinet/secretariats 403 affiche l\'erreur dans #list-result', async ({ page }) => {
  await page.route('**/v1/cabinet/secretariats', (route) => {
    if (route.request().method() !== 'GET') { route.continue(); return; }
    route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'forbidden' }),
    });
  });

  await page.goto('/admin/secretariats');
  const listSection = page.getByRole('region', { name: /Lister les secrétariats/ });
  await listSection.getByLabel(/Access token/).fill('non-admin-token');
  await listSection.getByRole('button', { name: 'GET' }).click();
  await expect(page.locator('#list-result')).toContainText('HTTP 403', { timeout: 5000 });
  await expect(page.locator('#list-result')).toContainText('forbidden');
});

// ── Happy path — POST /v1/cabinet/secretariats ─────────────────────────────

test('happy path — POST /v1/cabinet/secretariats 201 affiche le secrétariat créé', async ({ page }) => {
  await page.route('**/v1/cabinet/secretariats', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ id: 'cccc0000-0000-0000-0000-000000000001', name: 'Secrétariat Principal' }),
    });
  });

  await page.goto('/admin/secretariats');
  const createSection = page.getByRole('region', { name: /Créer un secrétariat/ });
  await createSection.getByLabel(/Access token/).fill('admin-bearer-token');
  await createSection.getByLabel(/Nom du secrétariat/).fill('Secrétariat Principal');
  await createSection.getByRole('button', { name: 'POST' }).click();
  await expect(page.locator('#create-result')).toContainText('HTTP 201', { timeout: 5000 });
  await expect(page.locator('#create-result')).toContainText('Secrétariat Principal');
});

// ── Error path — POST 422 ───────────────────────────────────────────────────

test('error path — POST /v1/cabinet/secretariats 422 affiche l\'erreur dans #create-result', async ({ page }) => {
  await page.route('**/v1/cabinet/secretariats', (route) => {
    if (route.request().method() !== 'POST') { route.continue(); return; }
    route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'invalid_name' }),
    });
  });

  await page.goto('/admin/secretariats');
  const createSection = page.getByRole('region', { name: /Créer un secrétariat/ });
  await createSection.getByLabel(/Access token/).fill('admin-bearer-token');
  await createSection.getByLabel(/Nom du secrétariat/).fill('');
  // Override required validation so the fetch fires
  await page.evaluate(() => {
    const input = document.querySelector('#create-form input[name="name"]') as HTMLInputElement;
    if (input) input.removeAttribute('required');
  });
  await createSection.getByRole('button', { name: 'POST' }).click();
  await expect(page.locator('#create-result')).toContainText('HTTP 422', { timeout: 5000 });
  await expect(page.locator('#create-result')).toContainText('invalid_name');
});

// ── Happy path — PATCH /v1/cabinet/secretariats/:id ───────────────────────

test('happy path — PATCH /v1/cabinet/secretariats/:id 200 affiche le secrétariat modifié', async ({ page }) => {
  const secretariatId = 'dddd0000-0000-0000-0000-000000000001';
  await page.route(`**/v1/cabinet/secretariats/${secretariatId}`, (route) => {
    if (route.request().method() !== 'PATCH') { route.continue(); return; }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ id: secretariatId, name: 'Nouveau Nom' }),
    });
  });

  await page.goto('/admin/secretariats');
  const editSection = page.getByRole('region', { name: /Modifier un secrétariat/ });
  await editSection.getByLabel(/Access token/).fill('admin-bearer-token');
  await editSection.getByLabel(/ID du secrétariat/).fill(secretariatId);
  await editSection.getByLabel(/Nouveau nom/).fill('Nouveau Nom');
  await editSection.getByRole('button', { name: 'PATCH' }).click();
  await expect(page.locator('#edit-result')).toContainText('HTTP 200', { timeout: 5000 });
  await expect(page.locator('#edit-result')).toContainText('Nouveau Nom');
});

// ── Happy path — DELETE via modale de confirmation ─────────────────────────

test('happy path — DELETE /v1/cabinet/secretariats/:id 204 après confirmation dans la modale', async ({ page }) => {
  const secretariatId = 'eeee0000-0000-0000-0000-000000000001';
  await page.route(`**/v1/cabinet/secretariats/${secretariatId}`, (route) => {
    if (route.request().method() !== 'DELETE') { route.continue(); return; }
    route.fulfill({ status: 204, body: '' });
  });

  await page.goto('/admin/secretariats');
  const deleteSection = page.getByRole('region', { name: /Supprimer un secrétariat/ });
  await deleteSection.getByLabel(/Access token/).fill('admin-bearer-token');
  await deleteSection.getByLabel(/ID du secrétariat à supprimer/).fill(secretariatId);
  await deleteSection.getByRole('button', { name: 'DELETE' }).click();

  // Confirmation dialog should appear
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible({ timeout: 3000 });
  await dialog.getByRole('button', { name: 'Supprimer' }).click();

  await expect(page.locator('#delete-result')).toContainText('HTTP 204', { timeout: 5000 });
});

// ── Error path — DELETE cancelled via modale ───────────────────────────────

test('error path — DELETE annulé depuis la modale ne déclenche pas l\'appel API', async ({ page }) => {
  let deleteCalled = false;
  await page.route('**/v1/cabinet/secretariats/**', (route) => {
    if (route.request().method() === 'DELETE') { deleteCalled = true; }
    route.continue();
  });

  await page.goto('/admin/secretariats');
  const deleteSection = page.getByRole('region', { name: /Supprimer un secrétariat/ });
  await deleteSection.getByLabel(/Access token/).fill('admin-bearer-token');
  await deleteSection.getByLabel(/ID du secrétariat à supprimer/).fill('ffff0000-0000-0000-0000-000000000001');
  await deleteSection.getByRole('button', { name: 'DELETE' }).click();

  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible({ timeout: 3000 });
  await dialog.getByRole('button', { name: 'Annuler' }).click();

  await expect(dialog).not.toBeVisible();
  expect(deleteCalled).toBe(false);
});
