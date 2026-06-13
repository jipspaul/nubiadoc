/**
 * EX1 — Réservation bout-en-bout (parcours cross-rôle)
 *
 * Parcours (contrat réel api/src/) :
 *   1. Patient réserve → POST /v1/appointments {provider_id, starts_at, motif}
 *      → 201 {appointment_id, status:"requested"}
 *   2. Praticien consulte son agenda → GET /v1/cabinet/agenda?date=YYYY-MM-DD
 *      → {practitioners, slots:[{id,…}]} contient le RDV
 *   3. Secrétaire confirme → POST /v1/cabinet/appointments/:id/confirm → 200
 *   4. Patient vérifie le statut → GET /v1/appointments/:id → status=confirmed
 *
 * Contrôle fuite cross-rôle :
 *   - GET /v1/appointments (patient) renvoie {data:[…]} sans patient_id : la
 *     fuite est vérifiée en créant un RDV pour un AUTRE patient du cabinet
 *     (via la secrétaire) et en s'assurant qu'il n'apparaît PAS dans la liste
 *     du patient connecté.
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed réel
 *             (seed.sql + seed_e2e.sql).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL              URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL          URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_ID        UUID provider (table provider) du praticien seed
 *   SEED_PRACTITIONER_TABLE_ID  UUID praticien (table practitioner) pour les créneaux
 *   SEED_OTHER_PATIENT_ID       UUID d'un autre patient du cabinet (contrôle fuite)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

// ID dans la table `provider` (marketplace) — exigé par POST /v1/appointments.
const SEED_PRACTITIONER_ID =
  process.env.SEED_PRACTITIONER_ID ?? 'f0000000-0000-0000-0000-0000000000f1';

// ID dans la table `practitioner` — exigé par POST /v1/cabinet/slots.
const SEED_PRACTITIONER_TABLE_ID =
  process.env.SEED_PRACTITIONER_TABLE_ID ?? 'c0000000-0000-0000-0000-0000000000c1';

// Autre patient du cabinet (≠ patient connecté) pour le contrôle de fuite.
const SEED_OTHER_PATIENT_ID =
  process.env.SEED_OTHER_PATIENT_ID ?? 'd0000000-0000-0000-0000-0000000000d5';

/**
 * Date de début aléatoire dans le futur (2 à 40 jours, heures ouvrées) pour
 * éviter la contrainte d'exclusion praticien (23P01 → 409 slot_taken)
 * entre les runs successifs sur un même stack.
 */
function randomFutureStart(): Date {
  const start = new Date();
  // Au-delà de l'horizon du pool de créneaux générés (30 j) pour éviter toute
  // collision EXCLUDE avec ces créneaux lors de la création (POST /v1/cabinet/slots).
  start.setDate(start.getDate() + 35 + Math.floor(Math.random() * 30));
  start.setHours(8 + Math.floor(Math.random() * 10), Math.floor(Math.random() * 4) * 15, 0, 0);
  return start;
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Parcours complet cross-rôle
// patient réserve → praticien voit dans l'agenda → secrétaire confirme
// → patient voit status=confirmed
// ─────────────────────────────────────────────────────────────────────────────
test('EX1 : patient réserve → praticien voit agenda → secrétaire confirme → patient status=confirmed', async ({ page }) => {
  // ── 1. Connexion patient ──────────────────────────────────────────────────
  await loginAs(page, 'patient');

  // ── 2. Patient : POST /v1/appointments → 201 ─────────────────────────────
  // Contrat réel : {provider_id, starts_at | slot_id, motif} — motif requis.
  const startsAt = randomFutureStart();
  const startsAtIso = startsAt.toISOString();
  const dateIso = startsAtIso.slice(0, 10);

  const { postStatus, appointmentId, initialStatus } = await page.evaluate(
    async ({
      apiBase,
      providerId,
      startsAt,
    }: {
      apiBase: string;
      providerId: string;
      startsAt: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const idempotencyKey = crypto.randomUUID();
      const resp = await fetch(`${apiBase}/v1/appointments`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
        body: JSON.stringify({
          provider_id: providerId,
          starts_at: startsAt,
          motif: 'consultation-EX1',
        }),
      });
      const text = await resp.text();
      let data: Record<string, unknown> = {};
      try {
        data = JSON.parse(text) as Record<string, unknown>;
      } catch {
        data = {};
      }
      return {
        postStatus: resp.status,
        appointmentId: (data['appointment_id'] ?? data['id'] ?? '') as string,
        initialStatus: (data['status'] ?? '') as string,
      };
    },
    { apiBase: API_BASE, providerId: SEED_PRACTITIONER_ID, startsAt: startsAtIso },
  );

  expect(postStatus, `POST /v1/appointments attendu 201, reçu ${postStatus}`).toBe(201);
  expect(appointmentId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  // Statut initial du contrat réel : "requested".
  expect(initialStatus).toBe('requested');

  // ── 3. Patient : GET /v1/appointments → RDV visible, status=requested ─────
  // Contrat réel : réponse enveloppée {data:[…]} sans patient_id.
  const patientListResult = await page.evaluate(
    async ({ apiBase, appointmentId }: { apiBase: string; appointmentId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      // RDV futur → filtre `upcoming` + grande limite (la liste par défaut est
      // paginée à 20 et saturée de RDV passés/annulés accumulés).
      const resp = await fetch(`${apiBase}/v1/appointments?status=upcoming&limit=100`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const body = resp.ok
        ? ((await resp.json()) as { data?: Array<{ id: string; status?: string }> })
        : {};
      const list = body.data ?? [];
      const found = list.find((a) => a.id === appointmentId);
      return { listStatus: resp.status, found };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(patientListResult.listStatus).toBeLessThan(300);
  expect(patientListResult.found).toBeDefined();
  expect(patientListResult.found?.status).toBe('requested');

  // ── 4. Déconnexion patient / connexion praticien ──────────────────────────
  await clearSession(page);
  await loginAs(page, 'practitioner');

  // ── 5. Praticien : GET /v1/cabinet/agenda?date=… → contient le RDV (200) ──
  // Contrat réel : {practitioners:[…], slots:[{id, …}]} — slots = RDV du jour.
  const agendaResult = await page.evaluate(
    async ({
      apiBase,
      date,
      appointmentId,
    }: {
      apiBase: string;
      date: string;
      appointmentId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/agenda?date=${encodeURIComponent(date)}`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      const text = await resp.text();
      let body: { slots?: Array<{ id: string }> } = {};
      try {
        body = JSON.parse(text) as { slots?: Array<{ id: string }> };
      } catch {
        body = {};
      }
      const found = (body.slots ?? []).some((s) => s.id === appointmentId);
      return { status: resp.status, found };
    },
    { apiBase: API_BASE, date: dateIso, appointmentId },
  );

  expect(agendaResult.status).toBe(200);
  expect(agendaResult.found, 'le RDV doit apparaître dans l’agenda praticien').toBe(true);

  // ── 6. Déconnexion praticien / connexion secrétaire ───────────────────────
  await clearSession(page);
  await loginAs(page, 'secretary');

  // ── 7. Secrétaire : POST /v1/cabinet/appointments/:id/confirm → 200 ───────
  const confirmResult = await page.evaluate(
    async ({ apiBase, appointmentId }: { apiBase: string; appointmentId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/appointments/${encodeURIComponent(appointmentId)}/confirm`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${jwt}` },
        },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(confirmResult.status).toBe(200);

  // ── 8. Déconnexion secrétaire / connexion patient ─────────────────────────
  await clearSession(page);
  await loginAs(page, 'patient');

  // ── 9. Patient : GET /v1/appointments/:id → status=confirmed ─────────────
  const getResult = await page.evaluate(
    async ({ apiBase, appointmentId }: { apiBase: string; appointmentId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/appointments/${encodeURIComponent(appointmentId)}`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      let data: { id?: string; status?: string } = {};
      if (resp.ok) {
        data = (await resp.json()) as { id?: string; status?: string };
      }
      return { status: resp.status, appointmentStatus: data.status };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(getResult.status).toBeLessThan(300);
  expect(getResult.appointmentStatus).toBe('confirmed');

  // ── 10. Reset — annuler le RDV créé (best effort, non bloquant) ───────────
  await page.evaluate(
    async ({ apiBase, appointmentId }: { apiBase: string; appointmentId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      await fetch(
        `${apiBase}/v1/appointments/${encodeURIComponent(appointmentId)}/cancel`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${jwt}` },
        },
      );
    },
    { apiBase: API_BASE, appointmentId },
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Absence de fuite cross-rôle
// Un RDV créé pour un AUTRE patient du cabinet (par la secrétaire) ne doit
// pas apparaître dans GET /v1/appointments du patient connecté.
// ─────────────────────────────────────────────────────────────────────────────
test('EX1 : aucune fuite cross-rôle — GET /v1/appointments retourne uniquement les RDV du patient connecté', async ({ page }) => {
  // ── 1. Connexion secrétaire : créer un RDV pour un AUTRE patient ──────────
  await loginAs(page, 'secretary');

  const start = randomFutureStart();
  const end = new Date(start.getTime() + 15 * 60 * 1000);

  const foreign = await page.evaluate(
    async ({
      apiBase,
      practitionerId,
      patientId,
      startsAt,
      endsAt,
    }: {
      apiBase: string;
      practitionerId: string;
      patientId: string;
      startsAt: string;
      endsAt: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      // Créneau ouvert (contrat : POST /v1/cabinet/slots {practitioner_id,…}).
      const slotResp = await fetch(`${apiBase}/v1/cabinet/slots`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          practitioner_id: practitionerId,
          starts_at: startsAt,
          ends_at: endsAt,
          status: 'open',
        }),
      });
      if (!slotResp.ok) return { ok: false, step: 'slot', status: slotResp.status, id: '' };
      const slot = (await slotResp.json()) as { id: string };

      // RDV pour l'autre patient (contrat : {patient_id, slot_id, notes?}).
      const apptResp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          patient_id: patientId,
          slot_id: slot.id,
          notes: 'EX1-leak-check',
        }),
      });
      if (!apptResp.ok) return { ok: false, step: 'appointment', status: apptResp.status, id: '' };
      const appt = (await apptResp.json()) as { appointment_id: string };
      return { ok: true, step: 'done', status: apptResp.status, id: appt.appointment_id };
    },
    {
      apiBase: API_BASE,
      practitionerId: SEED_PRACTITIONER_TABLE_ID,
      patientId: SEED_OTHER_PATIENT_ID,
      startsAt: start.toISOString(),
      endsAt: end.toISOString(),
    },
  );

  expect(
    foreign.ok,
    `création du RDV étranger (étape ${foreign.step}) attendu 201, reçu ${foreign.status}`,
  ).toBe(true);
  const foreignAppointmentId = foreign.id;

  // ── 2. Déconnexion secrétaire / connexion patient ─────────────────────────
  await clearSession(page);
  await loginAs(page, 'patient');

  // ── 3. GET /v1/me + GET /v1/appointments → aucune fuite ───────────────────
  const leakCheck = await page.evaluate(
    async ({ apiBase, foreignId }: { apiBase: string; foreignId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';

      const meResp = await fetch(`${apiBase}/v1/me`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      let me: { id?: string; user_id?: string; account_id?: string } = {};
      if (meResp.ok) {
        me = (await meResp.json()) as { id?: string; user_id?: string; account_id?: string };
      }
      // Contrat réel : /v1/me renvoie user_id + account_id (pas de champ id).
      const myId = me.user_id ?? me.id ?? '';

      const listResp = await fetch(`${apiBase}/v1/appointments`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const body = listResp.ok
        ? ((await listResp.json()) as { data?: Array<{ id: string }> })
        : {};
      const list = body.data ?? [];

      return {
        listStatus: listResp.status,
        myId,
        foreignVisible: list.some((a) => a.id === foreignId),
      };
    },
    { apiBase: API_BASE, foreignId: foreignAppointmentId },
  );

  expect(leakCheck.listStatus).toBeLessThan(300);
  expect(leakCheck.myId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  // Le RDV d'un autre patient ne doit pas apparaître
  expect(
    leakCheck.foreignVisible,
    'Fuite détectée : le RDV d’un autre patient est visible',
  ).toBe(false);
});
