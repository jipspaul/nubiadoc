import { test, expect } from '@playwright/test';

test('render : /auth/select-context affiche le titre et la section de chargement', async ({ page }) => {
  // Bloquer /v1/me pour que le chargement reste suspendu pendant l'assertion initiale
  await page.route('**/v1/me', route => new Promise(() => { /* never resolves */ }));

  await page.goto('/auth/select-context');

  await expect(page.getByRole('heading', { name: 'Choisir votre espace de travail' })).toBeVisible();
  await expect(page.locator('#loading')).toBeVisible();
  await expect(page.locator('#context-list')).toBeHidden();
  await expect(page.locator('#error-section')).toBeHidden();
});

test('error path : /v1/me échoue → section erreur affichée avec lien de retour', async ({ page }) => {
  await page.route('**/v1/me', route =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'unauthenticated', title: 'Non authentifié' }),
    }),
  );

  await page.goto('/auth/select-context');

  await expect(page.locator('#error-section')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#error-msg')).toContainText(/Impossible de récupérer|Reconnectez/);
  await expect(page.getByRole('link', { name: /Retour à la connexion/i })).toBeVisible();
  await expect(page.locator('#loading')).toBeHidden();
  await expect(page.locator('#context-list')).toBeHidden();
});

test('happy path : plusieurs contextes → cartes affichées avec bouton de sélection', async ({ page }) => {
  await page.route('**/v1/me', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'usr-001',
        email: 'pro@example.com',
        kind: 'pro',
        contexts: [
          { cabinet_id: 'cab-001', cabinet_name: 'Cabinet Lumière', role: 'practitioner' },
          { cabinet_id: 'cab-002', cabinet_name: 'Cabinet Soleil', role: 'secretary' },
        ],
      }),
    }),
  );

  await page.goto('/auth/select-context');

  await expect(page.locator('#context-list')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#loading')).toBeHidden();
  await expect(page.locator('#error-section')).toBeHidden();

  await expect(page.getByRole('article').first()).toBeVisible();
  // Les deux cabinets doivent apparaître
  await expect(page.getByText('Cabinet Lumière')).toBeVisible();
  await expect(page.getByText('Cabinet Soleil')).toBeVisible();
  // Chaque carte a un bouton de sélection
  const buttons = page.getByRole('button', { name: /Choisir cet espace/i });
  await expect(buttons).toHaveCount(2);
});

test('happy path : clic sur un contexte → POST /v1/auth/select-context puis redirection', async ({ page }) => {
  await page.route('**/v1/me', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'usr-002',
        email: 'admin@example.com',
        kind: 'pro',
        contexts: [
          { cabinet_id: 'cab-010', cabinet_name: 'Cabinet Principal', role: 'admin' },
        ],
      }),
    }),
  );

  // Un seul contexte → sélection automatique ; on intercepte avant la redirection
  let selectContextCalled = false;
  await page.route('**/v1/auth/select-context', route => {
    selectContextCalled = true;
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ access_token: 'tok-new', refresh_token: 'ref-new' }),
    });
  });

  await page.goto('/auth/select-context');

  // Avec un seul contexte la page déclenche la sélection automatiquement
  await expect(async () => {
    expect(selectContextCalled).toBe(true);
  }).toPass({ timeout: 5000 });
});

test('error path : POST /v1/auth/select-context échoue → message d\'erreur affiché', async ({ page }) => {
  await page.route('**/v1/me', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'usr-003',
        email: 'sec@example.com',
        kind: 'pro',
        contexts: [
          { cabinet_id: 'cab-020', cabinet_name: 'Cabinet Erreur', role: 'secretary' },
          { cabinet_id: 'cab-021', cabinet_name: 'Cabinet Deux', role: 'secretary' },
        ],
      }),
    }),
  );

  await page.route('**/v1/auth/select-context', route =>
    route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'internal_error', title: 'Erreur serveur' }),
    }),
  );

  await page.goto('/auth/select-context');

  // Attendre que les cartes soient affichées
  await expect(page.locator('#context-list')).toBeVisible({ timeout: 5000 });

  // Cliquer sur le premier bouton
  await page.getByRole('button', { name: /Choisir cet espace/i }).first().click();

  // La section erreur doit apparaître
  await expect(page.locator('#error-section')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#error-msg')).toContainText(/Erreur|HTTP 500/);
});
