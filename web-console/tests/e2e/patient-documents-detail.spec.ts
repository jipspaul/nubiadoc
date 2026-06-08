import { test, expect } from '@playwright/test';

const DOC_ID = '00000000-0000-0000-0000-000000000042';

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/documents/:id affiche le titre de chargement et le lien retour', async ({ page }) => {
  // Block API so loading state stays visible
  await page.route(`**/v1/documents/${DOC_ID}`, () => new Promise(() => {}));
  await page.goto(`/patient/documents/${DOC_ID}`);
  await expect(page.getByRole('heading', { name: /chargement/i })).toBeVisible();
  await expect(page.getByRole('link', { name: /retour à la liste/i })).toBeVisible();
});

// ─── happy path — document chargé ─────────────────────────────────────────

test('happy path — document chargé : métadonnées visibles et bouton télécharger actif', async ({ page }) => {
  await page.route(`**/v1/documents/${DOC_ID}`, (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: DOC_ID,
        name: 'Radio panoramique',
        type: 'radiographie',
        created_at: '2026-04-15T08:30:00Z',
      }),
    }),
  );
  await page.goto(`/patient/documents/${DOC_ID}`);

  await expect(page.getByRole('heading', { name: /radio panoramique/i })).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#doc-metadata')).toBeVisible();
  await expect(page.locator('#meta-name')).toContainText('Radio panoramique');
  await expect(page.locator('#meta-type')).toContainText('radiographie');
  await expect(page.getByRole('button', { name: /télécharger/i })).toBeEnabled();
});

// ─── happy path — téléchargement ──────────────────────────────────────────

test('happy path — clic télécharger : appel /download effectué', async ({ page }) => {
  await page.route(`**/v1/documents/${DOC_ID}`, (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: DOC_ID,
        name: 'Ordonnance',
        type: 'ordonnance',
        created_at: '2026-05-01T09:00:00Z',
      }),
    }),
  );

  let downloadCalled = false;
  await page.route(`**/v1/documents/${DOC_ID}/download`, (route) => {
    downloadCalled = true;
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ url: 'https://example.com/ordonnance.pdf' }),
    });
  });

  await page.goto(`/patient/documents/${DOC_ID}`);
  await expect(page.getByRole('button', { name: /télécharger/i })).toBeEnabled({ timeout: 5000 });
  await page.getByRole('button', { name: /télécharger/i }).click();

  await expect(async () => {
    expect(downloadCalled).toBe(true);
  }).toPass({ timeout: 5000 });
});

// ─── error path — API 404 ─────────────────────────────────────────────────

test('error path — GET 404 : titre "introuvable" et message d\'erreur affiché', async ({ page }) => {
  await page.route(`**/v1/documents/${DOC_ID}`, (route) =>
    route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'not_found' }),
    }),
  );
  await page.goto(`/patient/documents/${DOC_ID}`);

  await expect(page.getByRole('heading', { name: /introuvable/i })).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#doc-error')).toBeVisible();
  await expect(page.locator('#doc-error')).toContainText(/impossible/i);
  await expect(page.locator('#doc-metadata')).toBeHidden();
  await expect(page.getByRole('button', { name: /télécharger/i })).toBeDisabled();
});
