import { test, expect } from '@playwright/test';

const CONV_ID = '00000000-0000-0000-0000-000000000001';

function setupMocks(page: import('@playwright/test').Page, opts?: { msgStatus?: number; msgBody?: unknown; sendStatus?: number; readStatus?: number }): void {
  const msgStatus = opts?.msgStatus ?? 200;
  const msgBody = opts?.msgBody ?? [
    { id: 'msg-001', body: 'Bonjour, j\'ai une question.', sender_type: 'patient', created_at: '2026-06-01T10:00:00Z' },
    { id: 'msg-002', body: 'Bonjour, je vous aide.', sender_type: 'pro', created_at: '2026-06-01T10:05:00Z' },
  ];
  const readStatus = opts?.readStatus ?? 204;
  const sendStatus = opts?.sendStatus ?? 201;

  page.route(`**/v1/conversations/${CONV_ID}/messages`, (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({ status: msgStatus, contentType: 'application/json', body: JSON.stringify(msgBody) });
    } else {
      route.fulfill({ status: sendStatus, contentType: 'application/json', body: JSON.stringify({ id: 'msg-003', body: 'Nouveau.', sender_type: 'patient', created_at: new Date().toISOString() }) });
    }
  });
  page.route(`**/v1/conversations/${CONV_ID}/read`, (route) =>
    route.fulfill({ status: readStatus, body: '' }),
  );
}

// ─── render ────────────────────────────────────────────────────────────────

test('render — /patient/messages/:id affiche le loading et le lien retour', async ({ page }) => {
  // Block API so loading stays
  await page.route(`**/v1/conversations/${CONV_ID}/messages`, () => new Promise(() => {}));
  await page.route(`**/v1/conversations/${CONV_ID}/read`, () => new Promise(() => {}));
  await page.goto(`/patient/messages/${CONV_ID}`);
  await expect(page.locator('#msg-loading')).toBeVisible();
  await expect(page.getByRole('link', { name: /retour aux messages/i })).toBeVisible();
});

// ─── happy path — messages affichés ───────────────────────────────────────

test('happy path — messages chargés : bulles visibles + formulaire de réponse', async ({ page }) => {
  setupMocks(page);
  await page.goto(`/patient/messages/${CONV_ID}`);

  await expect(page.locator('[data-message-id="msg-001"]')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('[data-message-id="msg-001"]')).toContainText('Bonjour, j\'ai une question.');
  await expect(page.locator('[data-message-id="msg-002"]')).toContainText('Bonjour, je vous aide.');

  // Reply form visible
  await expect(page.locator('#reply-form')).toBeVisible();
  await expect(page.locator('textarea[name="body"]')).toBeVisible();
  await expect(page.getByRole('button', { name: /envoyer/i })).toBeVisible();
});

// ─── happy path — envoi de message ────────────────────────────────────────

test('happy path — envoi message : textarea vidé et liste rechargée', async ({ page }) => {
  let getCallCount = 0;
  page.route(`**/v1/conversations/${CONV_ID}/messages`, (route) => {
    if (route.request().method() === 'GET') {
      getCallCount++;
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([
          { id: 'msg-001', body: 'Bonjour.', sender_type: 'patient', created_at: '2026-06-01T10:00:00Z' },
        ]),
      });
    } else {
      // POST
      route.fulfill({ status: 201, contentType: 'application/json', body: JSON.stringify({ id: 'msg-new', body: 'Ma réponse.', sender_type: 'patient', created_at: new Date().toISOString() }) });
    }
  });
  page.route(`**/v1/conversations/${CONV_ID}/read`, (route) => route.fulfill({ status: 204, body: '' }));

  await page.goto(`/patient/messages/${CONV_ID}`);
  await expect(page.locator('#reply-form')).toBeVisible({ timeout: 5000 });

  await page.locator('textarea[name="body"]').fill('Ma réponse.');
  await page.getByRole('button', { name: /envoyer/i }).click();

  // After send, textarea should be cleared
  await expect(page.locator('textarea[name="body"]')).toHaveValue('', { timeout: 5000 });
  // GET was called at least twice (initial + after send)
  expect(getCallCount).toBeGreaterThanOrEqual(2);
});

// ─── error path — API 404 ─────────────────────────────────────────────────

test('error path — GET 404 : message d\'erreur, pas de formulaire', async ({ page }) => {
  await page.route(`**/v1/conversations/${CONV_ID}/messages`, (route) =>
    route.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify({ code: 'not_found' }) }),
  );
  await page.route(`**/v1/conversations/${CONV_ID}/read`, (route) => route.fulfill({ status: 204, body: '' }));

  await page.goto(`/patient/messages/${CONV_ID}`);
  await expect(page.locator('#msg-loading')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#msg-loading')).toContainText(/impossible/i);
  await expect(page.locator('#reply-form')).toBeHidden();
});
