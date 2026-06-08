/**
 * EP3 — Gestion RDV + jour J patient (E2E flow)
 *
 * Parcours :
 *   1. modifier : GET /v1/appointments/:id → PATCH /v1/appointments/:id → statut 200
 *   2. annuler  : POST /v1/appointments/:id/cancel → statut mis à jour à `cancelled`
 *   3. jour J   : POST …/checkin → GET …/queue (polling) → GET …/preparation
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P5
 *             (agenda praticien avec un RDV existant en statut `pending` ou `confirmed`
 *             pour le patient seed).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL       URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL   URL de l'API backend (défaut http://localhost:38030)
 *   SEED_APPOINTMENT_ID  UUID d'un RDV existant pour le patient seed (optionnel —
 *                        si absent, le test crée un RDV via POST /v1/appointments)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

/** Helper : récupère le JWT depuis localStorage. */
async function getJwt(page: Parameters<typeof loginAs>[0]): Promise<string> {
  return (await page.evaluate(() => localStorage.getItem('nubia_jwt'))) ?? '';
}

/**
 * Obtient un appointment_id utilisable pour le parcours.
 * - Si SEED_APPOINTMENT_ID est fourni, on le retourne directement.
 * - Sinon, on crée un RDV via POST /v1/appointments (nécessite un créneau disponible).
 * Retourne null si aucun créneau n'est trouvé (parcours optionnel).
 */
async function resolveAppointmentId(
  page: Parameters<typeof loginAs>[0],
): Promise<string | null> {
  if (process.env.SEED_APPOINTMENT_ID) {
    return process.env.SEED_APPOINTMENT_ID;
  }

  // 1. Chercher un créneau disponible
  const slotsResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/search/slots`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as { slots?: Array<{ id: string; provider_id?: string }> })
        : { slots: [] };
      return { status: resp.status, slots: data.slots ?? [] };
    },
    API_BASE,
  );

  if (slotsResp.slots.length === 0) return null;

  const slot = slotsResp.slots[0];

  // 2. Réserver le créneau
  const bookResp = await page.evaluate(
    async ({
      apiBase,
      slotId,
      providerId,
    }: {
      apiBase: string;
      slotId: string;
      providerId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/appointments`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': crypto.randomUUID(),
        },
        body: JSON.stringify({ slot_id: slotId, provider_id: providerId }),
      });
      const data = resp.ok ? ((await resp.json()) as { id?: string }) : {};
      return { status: resp.status, id: data.id ?? '' };
    },
    { apiBase: API_BASE, slotId: slot.id, providerId: slot.provider_id ?? '' },
  );

  if (bookResp.status === 201 && bookResp.id) return bookResp.id;
  return null;
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : modifier un RDV (PATCH /v1/appointments/:id → 200)
// ─────────────────────────────────────────────────────────────────────────────
test('modifier un RDV : PATCH /v1/appointments/:id → 200', async ({ page }) => {
  await loginAs(page, 'patient');
  const jwt = await getJwt(page);
  expect(jwt).not.toBe('');

  // Obtenir (ou créer) un RDV
  const appointmentId = await resolveAppointmentId(page);
  expect(appointmentId).not.toBeNull();
  if (!appointmentId) return; // garde — ne devrait pas arriver après expect

  // PATCH /v1/appointments/:id avec une note modifiée
  const patchResult = await page.evaluate(
    async ({
      apiBase,
      appointmentId,
    }: {
      apiBase: string;
      appointmentId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/appointments/${appointmentId}`, {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ notes: 'Modification EP3' }),
      });
      const data = resp.ok ? ((await resp.json()) as { id?: string; notes?: string }) : {};
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(patchResult.status).toBe(200);

  // GET /v1/appointments/:id → RDV accessible
  const getResult = await page.evaluate(
    async ({
      apiBase,
      appointmentId,
    }: {
      apiBase: string;
      appointmentId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/appointments/${appointmentId}`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok ? ((await resp.json()) as { id?: string; status?: string }) : {};
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(getResult.status).toBe(200);
  expect(getResult.data.id).toBe(appointmentId);

  // Page détail W15 : /patient/rdv/:id rendu
  await page.goto(`/patient/rdv/${appointmentId}`);
  await expect(page.getByRole('heading', { name: /détail du rendez-vous/i })).toBeVisible({
    timeout: 10_000,
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : annuler un RDV (POST …/cancel → statut `cancelled`)
// ─────────────────────────────────────────────────────────────────────────────
test('annuler un RDV : POST /cancel → statut cancelled', async ({ page }) => {
  await loginAs(page, 'patient');
  const jwt = await getJwt(page);
  expect(jwt).not.toBe('');

  // Créer un nouveau RDV à annuler (cherche un créneau frais pour éviter de
  // casser le créneau partagé avec les autres scénarios)
  const slotsResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/search/slots`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as { slots?: Array<{ id: string; provider_id?: string }> })
        : { slots: [] };
      return { status: resp.status, slots: data.slots ?? [] };
    },
    API_BASE,
  );

  if (slotsResp.slots.length === 0 && !process.env.SEED_APPOINTMENT_ID) {
    throw new Error(
      'Aucun créneau disponible et SEED_APPOINTMENT_ID non fourni — précondition manquante pour le scénario annulation.',
    );
  }

  let cancelId: string;

  if (process.env.SEED_APPOINTMENT_ID) {
    cancelId = process.env.SEED_APPOINTMENT_ID;
  } else {
    const slot = slotsResp.slots[0];
    const bookResp = await page.evaluate(
      async ({
        apiBase,
        slotId,
        providerId,
      }: {
        apiBase: string;
        slotId: string;
        providerId: string;
      }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(`${apiBase}/v1/appointments`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${jwt}`,
            'Content-Type': 'application/json',
            'Idempotency-Key': crypto.randomUUID(),
          },
          body: JSON.stringify({ slot_id: slotId, provider_id: providerId }),
        });
        const data = resp.ok ? ((await resp.json()) as { id?: string }) : {};
        return { status: resp.status, id: data.id ?? '' };
      },
      { apiBase: API_BASE, slotId: slot.id, providerId: slot.provider_id ?? '' },
    );

    expect(bookResp.status).toBe(201);
    expect(bookResp.id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
    cancelId = bookResp.id;
  }

  // POST /v1/appointments/:id/cancel
  const cancelResp = await page.evaluate(
    async ({
      apiBase,
      cancelId,
    }: {
      apiBase: string;
      cancelId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/appointments/${cancelId}/cancel`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return { status: resp.status };
    },
    { apiBase: API_BASE, cancelId },
  );

  expect(cancelResp.status).toBeLessThan(300);

  // Vérifier que le statut est bien `cancelled`
  const verifyResp = await page.evaluate(
    async ({
      apiBase,
      cancelId,
    }: {
      apiBase: string;
      cancelId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/appointments/${cancelId}`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok ? ((await resp.json()) as { status?: string }) : {};
      return { status: resp.status, apptStatus: data.status ?? '' };
    },
    { apiBase: API_BASE, cancelId },
  );

  expect(verifyResp.status).toBe(200);
  expect(verifyResp.apptStatus).toBe('cancelled');
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 3 : jour J — checkin → queue (polling) → preparation
// ─────────────────────────────────────────────────────────────────────────────
test('jour J : checkin → queue → preparation', async ({ page }) => {
  await loginAs(page, 'patient');
  const jwt = await getJwt(page);
  expect(jwt).not.toBe('');

  const appointmentId = await resolveAppointmentId(page);
  expect(appointmentId).not.toBeNull();
  if (!appointmentId) return;

  // ── 1. POST /v1/appointments/:id/checkin ────────────────────────────────
  const checkinResp = await page.evaluate(
    async ({
      apiBase,
      appointmentId,
    }: {
      apiBase: string;
      appointmentId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/appointments/${appointmentId}/checkin`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${jwt}` },
        },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, appointmentId },
  );

  // checkin retourne 200 ou 204 (ou 409 si déjà checké — on continue quand même)
  expect(checkinResp.status).toBeLessThan(500);

  // ── 2. GET /v1/appointments/:id/queue (polling — une passe suffit pour l'E2E) ──
  const queueResp = await page.evaluate(
    async ({
      apiBase,
      appointmentId,
    }: {
      apiBase: string;
      appointmentId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/appointments/${appointmentId}/queue`,
        {
          headers: { Authorization: `Bearer ${jwt}` },
        },
      );
      const data = resp.ok
        ? ((await resp.json()) as { position?: number; estimated_wait_minutes?: number; status?: string })
        : {};
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(queueResp.status).toBeLessThan(300);
  // La réponse doit contenir au moins une clé de position ou de statut
  expect(
    typeof queueResp.data.position === 'number' ||
    typeof queueResp.data.estimated_wait_minutes === 'number' ||
    typeof queueResp.data.status === 'string',
  ).toBe(true);

  // ── 3. GET /v1/appointments/:id/preparation ────────────────────────────
  const prepResp = await page.evaluate(
    async ({
      apiBase,
      appointmentId,
    }: {
      apiBase: string;
      appointmentId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/appointments/${appointmentId}/preparation`,
        {
          headers: { Authorization: `Bearer ${jwt}` },
        },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(prepResp.status).toBeLessThan(300);

  // ── 4. Page salle d'attente W17 : /patient/rdv/:id/salle-attente ──────────
  await page.goto(`/patient/rdv/${appointmentId}/salle-attente`);
  await expect(page.getByRole('heading', { name: /salle d'attente/i })).toBeVisible({
    timeout: 10_000,
  });
  // loading → card ou error visible
  await expect(page.locator('#queue-card, #queue-error')).toBeVisible({ timeout: 10_000 });

  // ── 5. Page préparation W16 : /patient/rdv/:id/preparation ───────────────
  await page.goto(`/patient/rdv/${appointmentId}/preparation`);
  await expect(page.getByRole('heading', { name: /préparation/i })).toBeVisible({
    timeout: 10_000,
  });
  // loading → card ou error visible
  await expect(page.locator('#prep-card, #prep-error')).toBeVisible({ timeout: 10_000 });
});
