/**
 * EX1 — Réservation bout-en-bout (parcours cross-rôle)
 *
 * Parcours :
 *   1. Patient réserve un créneau → POST /v1/appointments → 201
 *   2. Praticien consulte son agenda → GET /v1/cabinet/agenda → contient le RDV
 *   3. Secrétaire confirme → POST /v1/cabinet/appointments/:id/confirm → 200
 *   4. Patient vérifie le statut → GET /v1/appointments/:id → status=confirmed
 *
 * Contrôle fuite cross-rôle :
 *   - GET /v1/appointments (patient) ne liste que les RDV de ce patient
 *     (pas de données d'autres patients).
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2
 *             et seed P5 (praticien avec créneaux disponibles).
 *             R1 restauré (login pro porte cabinet_id+role dans le JWT).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL    URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_ID  UUID du praticien seed (pour la recherche de créneau)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SEED_PRACTITIONER_ID =
  process.env.SEED_PRACTITIONER_ID ?? '00000000-0000-0000-0000-000000000001';

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

  // ── 2. Récupérer un créneau disponible (praticien seed) ───────────────────
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowIso = tomorrow.toISOString().slice(0, 10);

  const slotsResult = await page.evaluate(
    async ({
      apiBase,
      providerId,
      date,
    }: {
      apiBase: string;
      providerId: string;
      date: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/search/slots?provider_id=${encodeURIComponent(providerId)}&from=${encodeURIComponent(date)}&to=${encodeURIComponent(date)}`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      const text = await resp.text();
      let data: { slots?: Array<{ id: string }> } = {};
      try {
        data = JSON.parse(text) as { slots?: Array<{ id: string }> };
      } catch {
        data = {};
      }
      return { status: resp.status, slots: data.slots ?? [] };
    },
    { apiBase: API_BASE, providerId: SEED_PRACTITIONER_ID, date: tomorrowIso },
  );

  expect(slotsResult.status).toBeLessThan(300);
  expect(slotsResult.slots.length).toBeGreaterThan(0);
  const slotId = slotsResult.slots[0].id;

  // ── 3. Patient : POST /v1/appointments → 201 ─────────────────────────────
  const { postStatus, appointmentId } = await page.evaluate(
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
      const idempotencyKey = crypto.randomUUID();
      const resp = await fetch(`${apiBase}/v1/appointments`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
        body: JSON.stringify({ slot_id: slotId, provider_id: providerId }),
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
        appointmentId: (data['id'] ?? data['appointment_id'] ?? '') as string,
      };
    },
    { apiBase: API_BASE, slotId, providerId: SEED_PRACTITIONER_ID },
  );

  expect(postStatus).toBe(201);
  expect(appointmentId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );

  // ── 4. Patient : GET /v1/appointments → status=pending ───────────────────
  const patientListResult = await page.evaluate(
    async ({ apiBase, appointmentId }: { apiBase: string; appointmentId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/appointments`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      let list: Array<{ id: string; status?: string; patient_id?: string }> = [];
      if (resp.ok) {
        list = (await resp.json()) as Array<{ id: string; status?: string; patient_id?: string }>;
      }
      const found = list.find((a) => a.id === appointmentId);
      // Contrôle fuite : tous les RDV listés doivent avoir le même patient_id
      const patientIds = list
        .filter((a) => a.patient_id !== undefined)
        .map((a) => a.patient_id as string);
      const uniquePatientIds = [...new Set(patientIds)];
      return {
        listStatus: resp.status,
        found,
        uniquePatientIds,
      };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(patientListResult.listStatus).toBeLessThan(300);
  expect(patientListResult.found).toBeDefined();
  expect(patientListResult.found?.status).toBe('pending');
  // Fuite cross-rôle : au plus un patient_id distinct dans la liste du patient
  expect(patientListResult.uniquePatientIds.length).toBeLessThanOrEqual(1);

  // ── 5. Déconnexion patient / connexion praticien ──────────────────────────
  await clearSession(page);
  await loginAs(page, 'practitioner');

  // ── 6. Praticien : GET /v1/cabinet/agenda → contient le RDV créé (200) ────
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
        `${apiBase}/v1/cabinet/agenda?from=${encodeURIComponent(date)}&to=${encodeURIComponent(date)}`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      const text = await resp.text();
      let entries: Array<{ appointments?: Array<{ id: string }> }> = [];
      try {
        entries = JSON.parse(text) as Array<{ appointments?: Array<{ id: string }> }>;
      } catch {
        entries = [];
      }
      const allAppts = entries.flatMap((e) => e.appointments ?? []);
      const found = allAppts.some((a) => a.id === appointmentId);
      return { status: resp.status, found };
    },
    { apiBase: API_BASE, date: tomorrowIso, appointmentId },
  );

  expect(agendaResult.status).toBe(200);
  expect(agendaResult.found).toBe(true);

  // ── 7. Déconnexion praticien / connexion secrétaire ───────────────────────
  await clearSession(page);
  await loginAs(page, 'secretary');

  // ── 8. Secrétaire : POST /v1/cabinet/appointments/:id/confirm → 200 ───────
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

  // ── 9. Déconnexion secrétaire / connexion patient ─────────────────────────
  await clearSession(page);
  await loginAs(page, 'patient');

  // ── 10. Patient : GET /v1/appointments/:id → status=confirmed ────────────
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

  // ── 11. Reset — annuler le RDV créé ──────────────────────────────────────
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
// Patient ne voit pas les RDV des autres patients dans GET /v1/appointments
// ─────────────────────────────────────────────────────────────────────────────
test('EX1 : aucune fuite cross-rôle — GET /v1/appointments retourne uniquement les RDV du patient connecté', async ({ page }) => {
  // ── 1. Connexion patient ──────────────────────────────────────────────────
  await loginAs(page, 'patient');

  // ── 2. GET /v1/appointments + GET /v1/me → patient_id cohérent ───────────
  const leakCheck = await page.evaluate(async (apiBase: string) => {
    const jwt = localStorage.getItem('nubia_jwt') ?? '';

    const meResp = await fetch(`${apiBase}/v1/me`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    let me: { id?: string } = {};
    if (meResp.ok) {
      me = (await meResp.json()) as { id?: string };
    }
    const myId = me.id ?? '';

    const listResp = await fetch(`${apiBase}/v1/appointments`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    let list: Array<{ id: string; patient_id?: string }> = [];
    if (listResp.ok) {
      list = (await listResp.json()) as Array<{ id: string; patient_id?: string }>;
    }

    // Vérifier qu'aucun RDV n'appartient à un autre patient
    const foreignAppts = list.filter(
      (a) => a.patient_id !== undefined && a.patient_id !== myId,
    );

    return {
      listStatus: listResp.status,
      myId,
      foreignCount: foreignAppts.length,
    };
  }, API_BASE);

  expect(leakCheck.listStatus).toBeLessThan(300);
  expect(leakCheck.myId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  // Aucun RDV d'un autre patient ne doit apparaître
  expect(leakCheck.foreignCount).toBe(0);
});
