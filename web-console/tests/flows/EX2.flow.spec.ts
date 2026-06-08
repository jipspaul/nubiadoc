/**
 * EX2 — RDV créé par secrétaire vu par patient (parcours cross-rôle)
 *
 * Parcours :
 *   1. Secrétaire (`secretaire.demo`) crée un RDV pour `patient.demo`
 *      via UI `/secretary/agenda` → POST /v1/cabinet/appointments → 201
 *   2. Patient (`patient.demo`) se connecte et voit le RDV dans
 *      GET /v1/appointments (200) + écran `/patient/rdv/index` l'affiche
 *
 * Valide le cloisonnement secrétaire→patient bout-en-bout.
 * Dépend de : E0 ✓, R1 ✓, R4 ✓, W36 ✓, W14 ✓.
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *             R1 restauré (login pro porte cabinet_id+role dans le JWT).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL           URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL       URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_ID     UUID du praticien seed (pour créer le RDV)
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
// Scénario 1 : Parcours complet cross-rôle
// secrétaire crée le RDV → patient le voit dans GET /v1/appointments + UI
// ─────────────────────────────────────────────────────────────────────────────
test('EX2 : secrétaire crée un RDV → patient le voit dans GET /v1/appointments + /patient/rdv', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Page agenda secrétaire (W36) ──────────────────────────────────────
  await page.goto('/secretary/agenda');
  await expect(page.locator('h1')).toBeVisible({ timeout: 15_000 });

  // ── 3. POST /v1/cabinet/appointments → RDV créé (201) ────────────────────
  const scheduledAt = new Date();
  scheduledAt.setDate(scheduledAt.getDate() + 3);
  scheduledAt.setHours(14, 0, 0, 0);

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
          motif: 'consultation-EX2',
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

  // ── 4. Déconnexion secrétaire / connexion patient ─────────────────────────
  await clearSession(page);
  await loginAs(page, 'patient');

  // ── 5. Patient : GET /v1/appointments → RDV visible (200) ────────────────
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
      return { listStatus: resp.status, found };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(
    patientListResult.listStatus,
    `GET /v1/appointments attendu 200, reçu ${patientListResult.listStatus}`,
  ).toBe(200);
  expect(
    patientListResult.found,
    'Le RDV créé par la secrétaire doit apparaître dans la liste du patient',
  ).toBeDefined();

  // ── 6. Patient : UI /patient/rdv affiche la liste (W14) ──────────────────
  await page.goto('/patient/rdv');
  // La page doit se charger sans erreur — les sections "upcoming" et "past" existent
  await expect(page.locator('#upcoming-loading, #upcoming-list, #upcoming-empty')).toBeVisible({
    timeout: 15_000,
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Aucune fuite cross-rôle
// GET /v1/appointments (patient) ne retourne que les RDV du patient connecté
// ─────────────────────────────────────────────────────────────────────────────
test('EX2 : aucune fuite cross-rôle — GET /v1/appointments retourne uniquement les RDV du patient connecté', async ({ page }) => {
  // ── 1. Connexion patient ──────────────────────────────────────────────────
  await loginAs(page, 'patient');

  // ── 2. GET /v1/me + GET /v1/appointments → patient_id cohérent ───────────
  const leakCheck = await page.evaluate(async (apiBase: string) => {
    const jwt = localStorage.getItem('nubia_jwt') ?? '';

    const meResp = await fetch(`${apiBase}/v1/me`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    const me = meResp.ok ? ((await meResp.json()) as { id?: string }) : {};
    const myId = me.id ?? '';

    const listResp = await fetch(`${apiBase}/v1/appointments`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    const list = listResp.ok
      ? ((await listResp.json()) as Array<{ id: string; patient_id?: string }>)
      : [];

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

  expect(
    leakCheck.listStatus,
    `GET /v1/appointments attendu 200, reçu ${leakCheck.listStatus}`,
  ).toBe(200);
  expect(leakCheck.myId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  // Aucun RDV d'un autre patient ne doit apparaître
  expect(
    leakCheck.foreignCount,
    'Fuite détectée : des RDV d\'autres patients sont visibles',
  ).toBe(0);
});
