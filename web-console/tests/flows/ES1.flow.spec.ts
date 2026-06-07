/**
 * ES1 — Parcours secrétaire Agenda (E2E flow)
 *
 * Valide le parcours bout-en-bout secrétaire sur l'agenda :
 * login → dashboard (GET /v1/cabinet/appointments 200)
 * → créer un RDV (POST /v1/cabinet/appointments 201)
 * → confirmer (POST …/:id/confirm 200)
 * → modifier (PATCH …/:id 200)
 *
 * Couvre W35 (secretary/dashboard) et W36 (secretary/agenda).
 * Route R4 (POST /v1/cabinet/appointments) déjà livrée.
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *             R1 restauré (login pro porte cabinet_id+role dans le JWT).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL           URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL       URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_ID     UUID du praticien seed (pour créer les RDV)
 *   SEED_PATIENT_ID          UUID du patient seed (bénéficiaire du RDV)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SEED_PRACTITIONER_ID =
  process.env.SEED_PRACTITIONER_ID ?? '00000000-0000-0000-0000-000000000001';

const SEED_PATIENT_ID =
  process.env.SEED_PATIENT_ID ?? '00000000-0000-0000-0000-000000000010';

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

  // ── 3. POST /v1/cabinet/appointments → RDV créé (201) ────────────────────
  const scheduledAt = new Date();
  scheduledAt.setDate(scheduledAt.getDate() + 2);
  scheduledAt.setHours(10, 0, 0, 0);

  const createResult = await page.evaluate(
    async ({
      apiBase,
      practitionerId,
      patientId,
      scheduledAt,
    }: {
      apiBase: string;
      practitionerId: string;
      patientId: string;
      scheduledAt: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          provider_id: practitionerId,
          patient_id: patientId,
          scheduled_at: scheduledAt,
          motif: 'consultation-ES1',
        }),
      });
      const data = resp.ok ? ((await resp.json()) as { id?: string }) : null;
      return { status: resp.status, data };
    },
    {
      apiBase: API_BASE,
      practitionerId: SEED_PRACTITIONER_ID,
      patientId: SEED_PATIENT_ID,
      scheduledAt: scheduledAt.toISOString(),
    },
  );

  expect(
    createResult.status,
    `POST /v1/cabinet/appointments attendu 201, reçu ${createResult.status}`,
  ).toBe(201);

  const appointmentId = createResult.data?.id;
  expect(appointmentId, 'id du RDV créé doit être présent').toBeTruthy();
  if (!appointmentId) return; // garde TypeScript

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

  // ── 5. PATCH /v1/cabinet/appointments/:id → modifié (200) ─────────────────
  const rescheduledAt = new Date(scheduledAt);
  rescheduledAt.setHours(11, 0, 0, 0);

  const patchStatus = await page.evaluate(
    async ({
      apiBase,
      id,
      scheduledAt,
    }: {
      apiBase: string;
      id: string;
      scheduledAt: string;
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
          body: JSON.stringify({ scheduled_at: scheduledAt }),
        },
      );
      return resp.status;
    },
    { apiBase: API_BASE, id: appointmentId, scheduledAt: rescheduledAt.toISOString() },
  );

  expect(
    patchStatus,
    `PATCH …/:id attendu 200, reçu ${patchStatus}`,
  ).toBe(200);
});
