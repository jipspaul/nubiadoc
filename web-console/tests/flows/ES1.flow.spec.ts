/**
 * ES1 — Parcours secrétaire Agenda (E2E flow)
 *
 * Valide le parcours bout-en-bout secrétaire sur l'agenda :
 * login → dashboard (GET /v1/cabinet/appointments 200)
 * → ouvrir un créneau (POST /v1/cabinet/slots 201)
 * → créer un RDV sur ce créneau (POST /v1/cabinet/appointments {patient_id, slot_id} 201)
 * → confirmer (POST …/:id/confirm 200)
 * → modifier (PATCH …/:id {starts_at} 200)
 *
 * Couvre W35 (secretary/dashboard) et W36 (secretary/agenda).
 * Contrat réel (api/src/scheduling.rs) :
 *   POST /v1/cabinet/appointments body = {patient_id, slot_id, notes?}
 *   → réponse {appointment_id, status:"requested"}.
 *   PATCH …/:id body = {starts_at?, motif?}.
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed réel
 *             (seed.sql + seed_e2e.sql).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL              URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL          URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_TABLE_ID  UUID praticien (table practitioner) pour le créneau
 *   SEED_PATIENT_ID             UUID du patient seed (bénéficiaire du RDV)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

// ID dans la table `practitioner` (≠ provider) — exigé par POST /v1/cabinet/slots.
const SEED_PRACTITIONER_TABLE_ID =
  process.env.SEED_PRACTITIONER_TABLE_ID ?? 'c0000000-0000-0000-0000-0000000000c1';

const SEED_PATIENT_ID =
  process.env.SEED_PATIENT_ID ?? 'd0000000-0000-0000-0000-0000000000d1';

/**
 * Fenêtre horaire aléatoire dans le futur (2 à 40 jours, heures ouvrées) pour
 * éviter les collisions avec la contrainte d'exclusion praticien (23P01)
 * entre les runs successifs sur un même stack.
 */
function randomFutureWindow(): { startsAt: string; endsAt: string } {
  const start = new Date();
  // Au-delà de l'horizon du pool de créneaux générés (30 j) pour éviter toute
  // collision EXCLUDE lors de la création (POST /v1/cabinet/slots).
  start.setDate(start.getDate() + 35 + Math.floor(Math.random() * 30));
  start.setHours(8 + Math.floor(Math.random() * 10), Math.floor(Math.random() * 4) * 15, 0, 0);
  const end = new Date(start.getTime() + 15 * 60 * 1000);
  return { startsAt: start.toISOString(), endsAt: end.toISOString() };
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : login secrétaire → dashboard chargé (GET /v1/cabinet/appointments 200)
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire : login → dashboard → GET /v1/cabinet/appointments retourne 200', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Page dashboard secrétaire (W35) ───────────────────────────────────
  await page.goto('/secretary/dashboard');
  await expect(page.locator('h1')).toBeVisible({ timeout: 15_000 });

  // ── 3. GET /v1/cabinet/appointments → 200 ────────────────────────────────
  const apptStatus = await page.evaluate(async (apiBase: string) => {
    const jwt = localStorage.getItem('nubia_jwt') ?? '';
    const resp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    return resp.status;
  }, API_BASE);

  expect(
    apptStatus,
    `GET /v1/cabinet/appointments attendu 200, reçu ${apptStatus}`,
  ).toBe(200);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : créer RDV (201) → confirmer (200) → modifier (200)
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire : POST appointment (201) → confirm (200) → PATCH (200)', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Page agenda secrétaire (W36) ──────────────────────────────────────
  await page.goto('/secretary/agenda');
  await expect(page.locator('h1')).toBeVisible({ timeout: 15_000 });

  // ── 3a. POST /v1/cabinet/slots → créneau ouvert (201) ────────────────────
  const window = randomFutureWindow();

  const slotResult = await page.evaluate(
    async ({
      apiBase,
      practitionerId,
      startsAt,
      endsAt,
    }: {
      apiBase: string;
      practitionerId: string;
      startsAt: string;
      endsAt: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/slots`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          practitioner_id: practitionerId,
          starts_at: startsAt,
          ends_at: endsAt,
          status: 'open',
          motif: 'consultation-ES1',
        }),
      });
      const data = resp.ok ? ((await resp.json()) as { id?: string }) : null;
      return { status: resp.status, slotId: data?.id ?? '' };
    },
    {
      apiBase: API_BASE,
      practitionerId: SEED_PRACTITIONER_TABLE_ID,
      startsAt: window.startsAt,
      endsAt: window.endsAt,
    },
  );

  expect(
    slotResult.status,
    `POST /v1/cabinet/slots attendu 201, reçu ${slotResult.status}`,
  ).toBe(201);
  expect(slotResult.slotId, 'id du créneau créé doit être présent').toBeTruthy();

  // ── 3b. POST /v1/cabinet/appointments {patient_id, slot_id} → 201 ────────
  const createResult = await page.evaluate(
    async ({
      apiBase,
      patientId,
      slotId,
    }: {
      apiBase: string;
      patientId: string;
      slotId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          patient_id: patientId,
          slot_id: slotId,
          notes: 'consultation-ES1',
        }),
      });
      const data = resp.ok
        ? ((await resp.json()) as { appointment_id?: string; status?: string })
        : null;
      return { status: resp.status, data };
    },
    {
      apiBase: API_BASE,
      patientId: SEED_PATIENT_ID,
      slotId: slotResult.slotId,
    },
  );

  expect(
    createResult.status,
    `POST /v1/cabinet/appointments attendu 201, reçu ${createResult.status}`,
  ).toBe(201);

  const appointmentId = createResult.data?.appointment_id;
  expect(appointmentId, 'appointment_id du RDV créé doit être présent').toBeTruthy();
  if (!appointmentId) return; // garde TypeScript
  expect(createResult.data?.status, 'statut initial attendu : requested').toBe('requested');

  // ── 4. POST /v1/cabinet/appointments/:id/confirm → confirmé (200) ─────────
  const confirmStatus = await page.evaluate(
    async ({ apiBase, id }: { apiBase: string; id: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/appointments/${encodeURIComponent(id)}/confirm`,
        { method: 'POST', headers: { Authorization: `Bearer ${jwt}` } },
      );
      return resp.status;
    },
    { apiBase: API_BASE, id: appointmentId },
  );

  expect(
    confirmStatus,
    `POST …/confirm attendu 200, reçu ${confirmStatus}`,
  ).toBe(200);

  // ── 5. PATCH /v1/cabinet/appointments/:id {starts_at} → modifié (200) ─────
  // Décale le RDV de 1 h (la durée est préservée par l'API).
  const rescheduledAt = new Date(new Date(window.startsAt).getTime() + 60 * 60 * 1000);

  const patchStatus = await page.evaluate(
    async ({
      apiBase,
      id,
      startsAt,
    }: {
      apiBase: string;
      id: string;
      startsAt: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/appointments/${encodeURIComponent(id)}`,
        {
          method: 'PATCH',
          headers: {
            Authorization: `Bearer ${jwt}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ starts_at: startsAt }),
        },
      );
      return resp.status;
    },
    { apiBase: API_BASE, id: appointmentId, startsAt: rescheduledAt.toISOString() },
  );

  expect(
    patchStatus,
    `PATCH …/:id attendu 200, reçu ${patchStatus}`,
  ).toBe(200);
});
