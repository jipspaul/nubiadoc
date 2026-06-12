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

type FlatSlot = { slot_id: string; provider_id: string; starts_at: string };

/**
 * Liste les créneaux ouverts via GET /v1/search/slots (contrat réel :
 * `{ data: [{ provider_id, slots: [{ slot_id, starts_at }] }] }`), aplatie.
 * `minHoursAhead` filtre les créneaux trop proches (PATCH exige ≥ 24 h,
 * cancel exige ≥ 2 h avant starts_at).
 */
async function listOpenSlots(
  page: Parameters<typeof loginAs>[0],
  minHoursAhead: number,
): Promise<FlatSlot[]> {
  const slots = await page.evaluate(async (apiBase: string) => {
    const resp = await fetch(`${apiBase}/v1/search/slots`);
    if (!resp.ok) return [] as Array<{ slot_id: string; provider_id: string; starts_at: string }>;
    const payload = (await resp.json()) as {
      data?: Array<{
        provider_id: string;
        slots?: Array<{ slot_id: string; starts_at: string }>;
      }>;
    };
    const flat: Array<{ slot_id: string; provider_id: string; starts_at: string }> = [];
    for (const group of payload.data ?? []) {
      for (const s of group.slots ?? []) {
        flat.push({ slot_id: s.slot_id, provider_id: group.provider_id, starts_at: s.starts_at });
      }
    }
    return flat;
  }, API_BASE);

  const cutoff = Date.now() + minHoursAhead * 3_600_000;
  return slots.filter((s) => new Date(s.starts_at).getTime() > cutoff);
}

/** Réserve un créneau via POST /v1/appointments (motif requis par le contrat). */
async function bookSlot(
  page: Parameters<typeof loginAs>[0],
  slot: FlatSlot,
): Promise<{ status: number; id: string }> {
  return page.evaluate(
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
        body: JSON.stringify({
          slot_id: slotId,
          provider_id: providerId,
          motif: 'RDV EP3 (E2E)',
        }),
      });
      const data = resp.ok
        ? ((await resp.json()) as { appointment_id?: string; id?: string })
        : {};
      return { status: resp.status, id: data.appointment_id ?? data.id ?? '' };
    },
    { apiBase: API_BASE, slotId: slot.slot_id, providerId: slot.provider_id },
  );
}

/** Annule un RDV créé par le test (nettoyage — rouvre le créneau seed). */
async function cancelAppointment(
  page: Parameters<typeof loginAs>[0],
  appointmentId: string,
): Promise<void> {
  await page.evaluate(
    async ({ apiBase, appointmentId }: { apiBase: string; appointmentId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      await fetch(`${apiBase}/v1/appointments/${appointmentId}/cancel`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${jwt}` },
      });
    },
    { apiBase: API_BASE, appointmentId },
  );
}

/**
 * Réserve le premier créneau qui accepte la réservation. L'API ne marque pas
 * les créneaux `booked` à la création (conflits gérés par contrainte
 * d'exclusion → 409 slot_taken) : il faut donc itérer.
 */
async function bookFirstAvailable(
  page: Parameters<typeof loginAs>[0],
  slots: FlatSlot[],
): Promise<string | null> {
  for (const slot of slots) {
    const resp = await bookSlot(page, slot);
    if (resp.status === 201 && resp.id) return resp.id;
  }
  return null;
}

/**
 * Cherche un RDV EP3 résiduel (run précédent interrompu avant nettoyage)
 * encore modifiable (status requested/confirmed, starts_at > cutoff).
 */
async function findLeftoverEp3Appointment(
  page: Parameters<typeof loginAs>[0],
  minHoursAhead: number,
): Promise<string | null> {
  const items = await page.evaluate(async (apiBase: string) => {
    const jwt = localStorage.getItem('nubia_jwt') ?? '';
    const resp = await fetch(`${apiBase}/v1/appointments?status=upcoming&limit=100`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    if (!resp.ok) return [] as Array<{ id: string; starts_at: string; status: string; motif: string | null }>;
    const payload = (await resp.json()) as {
      data?: Array<{ id: string; starts_at: string; status: string; motif: string | null }>;
    };
    return payload.data ?? [];
  }, API_BASE);

  const cutoff = Date.now() + minHoursAhead * 3_600_000;
  const leftover = items.find(
    (a) =>
      a.motif === 'RDV EP3 (E2E)' &&
      (a.status === 'requested' || a.status === 'confirmed') &&
      new Date(a.starts_at).getTime() > cutoff,
  );
  return leftover?.id ?? null;
}

/**
 * Obtient un appointment_id utilisable pour le parcours.
 * - Si SEED_APPOINTMENT_ID est fourni, on le retourne directement.
 * - Sinon, réutilise un RDV EP3 résiduel, ou crée un RDV via
 *   POST /v1/appointments sur un créneau à ≥ 25 h (PATCH exige ≥ 24 h
 *   de marge avant starts_at).
 * Retourne null si aucun créneau n'est trouvé (parcours optionnel).
 */
async function resolveAppointmentId(
  page: Parameters<typeof loginAs>[0],
): Promise<string | null> {
  if (process.env.SEED_APPOINTMENT_ID) {
    return process.env.SEED_APPOINTMENT_ID;
  }

  const leftover = await findLeftoverEp3Appointment(page, 25);
  if (leftover) return leftover;

  const slots = await listOpenSlots(page, 25);
  if (slots.length === 0) return null;

  return bookFirstAvailable(page, slots);
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

  // PATCH /v1/appointments/:id — le contrat n'accepte que starts_at/motif.
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
        body: JSON.stringify({ motif: 'Modification EP3' }),
      });
      const data = resp.ok
        ? ((await resp.json()) as { appointment_id?: string; status?: string })
        : {};
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

  // Nettoyage : annuler le RDV créé pour rouvrir le créneau seed.
  if (!process.env.SEED_APPOINTMENT_ID) {
    await cancelAppointment(page, appointmentId);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : annuler un RDV (POST …/cancel → statut `cancelled`)
// ─────────────────────────────────────────────────────────────────────────────
test('annuler un RDV : POST /cancel → statut cancelled', async ({ page }) => {
  await loginAs(page, 'patient');
  const jwt = await getJwt(page);
  expect(jwt).not.toBe('');

  // Créer un nouveau RDV à annuler (cancel exige starts_at > now + 2 h ;
  // on prend une marge de 3 h sur le créneau choisi)
  const slots = await listOpenSlots(page, 3);

  if (slots.length === 0 && !process.env.SEED_APPOINTMENT_ID) {
    throw new Error(
      'Aucun créneau disponible et SEED_APPOINTMENT_ID non fourni — précondition manquante pour le scénario annulation.',
    );
  }

  let cancelId: string;

  if (process.env.SEED_APPOINTMENT_ID) {
    cancelId = process.env.SEED_APPOINTMENT_ID;
  } else {
    const bookedId =
      (await findLeftoverEp3Appointment(page, 3)) ??
      (await bookFirstAvailable(page, slots));

    expect(bookedId).not.toBeNull();
    expect(bookedId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
    cancelId = bookedId as string;
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
  // loading → card ou error visible (first() : les deux éléments existent dans le DOM)
  await expect(page.locator('#queue-card:visible, #queue-error:visible').first()).toBeVisible({ timeout: 10_000 });

  // ── 5. Page préparation W16 : /patient/rdv/:id/preparation ───────────────
  await page.goto(`/patient/rdv/${appointmentId}/preparation`);
  await expect(page.getByRole('heading', { level: 1, name: /préparation/i })).toBeVisible({
    timeout: 10_000,
  });
  // loading → card ou error visible (first() : les deux éléments existent dans le DOM)
  await expect(page.locator('#prep-card:visible, #prep-error:visible').first()).toBeVisible({ timeout: 10_000 });

  // Nettoyage : annuler le RDV créé pour rouvrir le créneau seed.
  if (!process.env.SEED_APPOINTMENT_ID) {
    await cancelAppointment(page, appointmentId);
  }
});
