/**
 * EP6 — Soins + profil patient (E2E flow)
 *
 * Parcours :
 *   1. Soins       : GET /v1/treatment-plans liste → détail
 *                    GET /v1/implant-passport/export → fichier reçu
 *   2. Consentements : GET /v1/account/consents → liste
 *                      PUT /v1/account/consents/:purpose → 200
 *   3. Notifications : GET /v1/account/notification-preferences → 200
 *                      PATCH /v1/account/notification-preferences → 200
 *                      GET /v1/notifications → liste
 *                      GET /v1/reminders → liste
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL       URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL   URL de l'API backend (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

/** Helper : récupère le JWT depuis localStorage. */
async function getJwt(page: Parameters<typeof loginAs>[0]): Promise<string> {
  return (await page.evaluate(() => localStorage.getItem('nubia_jwt'))) ?? '';
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Plan de traitement liste → détail + passeport export
// ─────────────────────────────────────────────────────────────────────────────
test('plan de traitement : GET /v1/treatment-plans liste → détail ; export passeport', async ({ page }) => {
  await loginAs(page, 'patient');
  const jwt = await getJwt(page);
  expect(jwt).not.toBe('');

  // ── 1. GET /v1/treatment-plans → liste ────────────────────────────────────
  const listResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/treatment-plans`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as Array<{ id: string; title?: string; status?: string }>)
        : [];
      return { status: resp.status, plans: data };
    },
    API_BASE,
  );

  expect(listResp.status).toBeLessThan(300);
  expect(Array.isArray(listResp.plans)).toBe(true);

  // ── 2. Page /patient/soins/plan : chargement de la liste ──────────────────
  await page.goto('/patient/soins/plan');
  // Attendre la fin du chargement (spinner masqué)
  await expect(page.locator('#plans-loading')).toBeHidden({ timeout: 15_000 });
  // La liste ou le message vide doit être visible
  await expect(
    page.locator('#plans-list, #plans-empty, #plans-error'),
  ).toBeVisible({ timeout: 10_000 });

  // ── 3. Si au moins un plan : ouvrir le détail ─────────────────────────────
  if (listResp.plans.length > 0) {
    const firstPlanId = listResp.plans[0].id;

    // GET /v1/treatment-plans/:id → détail
    const detailResp = await page.evaluate(
      async ({ apiBase, planId }: { apiBase: string; planId: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(`${apiBase}/v1/treatment-plans/${planId}`, {
          headers: { Authorization: `Bearer ${jwt}` },
        });
        const data = resp.ok
          ? ((await resp.json()) as { id: string; title?: string; status?: string })
          : null;
        return { status: resp.status, data };
      },
      { apiBase: API_BASE, planId: firstPlanId },
    );

    expect(detailResp.status).toBe(200);
    expect(detailResp.data?.id).toBe(firstPlanId);

    // Clic sur le premier plan dans l'UI → section détail visible
    const firstBtn = page.locator('.plan-item').first();
    await expect(firstBtn).toBeVisible({ timeout: 10_000 });
    await firstBtn.click();

    await expect(page.locator('#plan-detail')).not.toHaveAttribute('hidden');
    await expect(page.locator('#detail-loading')).toBeHidden({ timeout: 10_000 });
    await expect(page.locator('#detail-content')).not.toHaveAttribute('hidden');
  }

  // ── 4. GET /v1/implant-passport/export → fichier reçu ─────────────────────
  const exportResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/implant-passport/export`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return { status: resp.status };
    },
    API_BASE,
  );

  // L'export doit répondre (200 avec URL ou 204 si pas de données)
  expect(exportResp.status).toBeLessThan(300);

  // ── 5. Page /patient/soins/passeport : bouton export cliquable ─────────────
  await page.goto('/patient/soins/passeport');
  await expect(page.locator('#passport-loading')).toBeHidden({ timeout: 15_000 });
  await expect(page.locator('#btn-export')).toBeVisible();
  await expect(page.locator('#btn-export')).toBeEnabled();
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Consentements liste → toggle (PUT)
// ─────────────────────────────────────────────────────────────────────────────
test('consentements : GET /v1/account/consents liste ; PUT /v1/account/consents/:purpose → 200', async ({ page }) => {
  await loginAs(page, 'patient');
  const jwt = await getJwt(page);
  expect(jwt).not.toBe('');

  // ── 1. GET /v1/account/consents → liste ───────────────────────────────────
  const consentsResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/account/consents`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as Array<{ purpose: string; granted: boolean }>)
        : [];
      return { status: resp.status, consents: data };
    },
    API_BASE,
  );

  expect(consentsResp.status).toBeLessThan(300);
  expect(Array.isArray(consentsResp.consents)).toBe(true);

  // ── 2. PUT /v1/account/consents/:purpose → 200 ────────────────────────────
  if (consentsResp.consents.length > 0) {
    const first = consentsResp.consents[0];
    const newValue = !first.granted;

    const putResp = await page.evaluate(
      async ({
        apiBase,
        purpose,
        granted,
      }: {
        apiBase: string;
        purpose: string;
        granted: boolean;
      }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(
          `${apiBase}/v1/account/consents/${encodeURIComponent(purpose)}`,
          {
            method: 'PUT',
            headers: {
              Authorization: `Bearer ${jwt}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ granted }),
          },
        );
        const data = resp.ok
          ? ((await resp.json()) as { purpose: string; granted: boolean })
          : null;
        return { status: resp.status, data };
      },
      { apiBase: API_BASE, purpose: first.purpose, granted: newValue },
    );

    expect(putResp.status).toBe(200);
    expect(putResp.data?.purpose).toBe(first.purpose);
    expect(putResp.data?.granted).toBe(newValue);

    // Remettre à l'état d'origine (cleanup)
    await page.evaluate(
      async ({
        apiBase,
        purpose,
        granted,
      }: {
        apiBase: string;
        purpose: string;
        granted: boolean;
      }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        await fetch(
          `${apiBase}/v1/account/consents/${encodeURIComponent(purpose)}`,
          {
            method: 'PUT',
            headers: {
              Authorization: `Bearer ${jwt}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ granted }),
          },
        );
      },
      { apiBase: API_BASE, purpose: first.purpose, granted: first.granted },
    );
  }

  // ── 3. Page /patient/profil/consentements : liste chargée ─────────────────
  await page.goto('/patient/profil/consentements');
  await expect(page.locator('#consents-loading')).toBeHidden({ timeout: 15_000 });
  await expect(
    page.locator('#consents-list, #consents-error'),
  ).toBeVisible({ timeout: 10_000 });
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 3 : Préférences de notification + centre de notifications
// ─────────────────────────────────────────────────────────────────────────────
test('notifications : GET/PATCH notification-preferences → 200 ; GET notifications + reminders → liste', async ({ page }) => {
  await loginAs(page, 'patient');
  const jwt = await getJwt(page);
  expect(jwt).not.toBe('');

  // ── 1. GET /v1/account/notification-preferences → 200 ─────────────────────
  const getPrefsResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/account/notification-preferences`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      const data = resp.ok
        ? ((await resp.json()) as { email?: boolean; sms?: boolean; push?: boolean })
        : null;
      return { status: resp.status, data };
    },
    API_BASE,
  );

  expect(getPrefsResp.status).toBe(200);
  expect(getPrefsResp.data).not.toBeNull();

  // ── 2. PATCH /v1/account/notification-preferences → 200 ───────────────────
  // On envoie les mêmes valeurs (no-op patch) pour vérifier le contrat.
  const currentEmail = getPrefsResp.data?.email ?? false;

  const patchPrefsResp = await page.evaluate(
    async ({
      apiBase,
      emailValue,
    }: {
      apiBase: string;
      emailValue: boolean;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/account/notification-preferences`,
        {
          method: 'PATCH',
          headers: {
            Authorization: `Bearer ${jwt}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ email: emailValue }),
        },
      );
      const data = resp.ok
        ? ((await resp.json()) as { email?: boolean; sms?: boolean; push?: boolean })
        : null;
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, emailValue: currentEmail },
  );

  expect(patchPrefsResp.status).toBe(200);
  expect(patchPrefsResp.data).not.toBeNull();

  // ── 3. GET /v1/notifications → liste ──────────────────────────────────────
  const notifResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/notifications`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok ? await resp.json() : null;
      return { status: resp.status, data };
    },
    API_BASE,
  );

  expect(notifResp.status).toBeLessThan(300);
  // La réponse doit être un tableau ou un objet paginé
  const isArray = Array.isArray(notifResp.data);
  const isPaged =
    typeof notifResp.data === 'object' &&
    notifResp.data !== null &&
    ('data' in (notifResp.data as object) || 'items' in (notifResp.data as object));
  expect(isArray || isPaged).toBe(true);

  // ── 4. GET /v1/reminders → liste ──────────────────────────────────────────
  const remindersResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/reminders`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok ? await resp.json() : null;
      return { status: resp.status, data };
    },
    API_BASE,
  );

  expect(remindersResp.status).toBeLessThan(300);
  expect(Array.isArray(remindersResp.data)).toBe(true);
});
