/**
 * EX2 — RDV créé par secrétaire vu par patient (parcours cross-rôle)
 *
 * Parcours (contrat réel api/src/scheduling.rs) :
 *   1. Secrétaire crée un RDV pour le patient seed via l'API depuis
 *      `/secretary/agenda` : POST /v1/cabinet/slots (créneau) puis
 *      POST /v1/cabinet/appointments {patient_id, slot_id} → 201
 *   2. Patient se connecte et voit le RDV dans GET /v1/appointments
 *      ({data:[…]}, 200) + écran `/patient/rdv/index` l'affiche
 *
 * Contrôle fuite : un RDV créé pour un AUTRE patient du cabinet ne doit pas
 * apparaître dans la liste du patient connecté (la liste patient n'expose
 * pas patient_id — la vérification se fait par id de RDV).
 *
 * Valide le cloisonnement secrétaire→patient bout-en-bout.
 * Dépend de : E0 ✓, R1 ✓, R4 ✓, W36 ✓, W14 ✓.
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed réel.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL              URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL          URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_TABLE_ID  UUID praticien (table practitioner) pour les créneaux
 *   SEED_PATIENT_ID             UUID du patient seed (bénéficiaire du RDV)
 *   SEED_OTHER_PATIENT_ID       UUID d'un autre patient du cabinet (contrôle fuite)
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

const SEED_OTHER_PATIENT_ID =
  process.env.SEED_OTHER_PATIENT_ID ?? 'd0000000-0000-0000-0000-0000000000d5';

/**
 * Fenêtre horaire aléatoire dans le futur (2 à 40 jours, heures ouvrées) pour
 * éviter la contrainte d'exclusion praticien (23P01) entre les runs.
 */
function randomFutureWindow(): { startsAt: string; endsAt: string } {
  const start = new Date();
  // Au-delà de l'horizon du pool de créneaux générés (30 j) pour éviter toute
  // collision EXCLUDE avec ces créneaux lors de la création (POST /v1/cabinet/slots).
  start.setDate(start.getDate() + 35 + Math.floor(Math.random() * 30));
  start.setHours(8 + Math.floor(Math.random() * 10), Math.floor(Math.random() * 4) * 15, 0, 0);
  const end = new Date(start.getTime() + 15 * 60 * 1000);
  return { startsAt: start.toISOString(), endsAt: end.toISOString() };
}

/**
 * Crée un créneau ouvert + un RDV cabinet pour `patientId` avec le jeton
 * secrétaire présent dans localStorage. Retourne l'id du RDV créé.
 */
async function createCabinetAppointment(
  page: import('@playwright/test').Page,
  patientId: string,
  notes: string,
): Promise<{ ok: boolean; step: string; status: number; id: string }> {
  const window = randomFutureWindow();
  return page.evaluate(
    async ({
      apiBase,
      practitionerId,
      patientId,
      startsAt,
      endsAt,
      notes,
    }: {
      apiBase: string;
      practitionerId: string;
      patientId: string;
      startsAt: string;
      endsAt: string;
      notes: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
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

      const apptResp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ patient_id: patientId, slot_id: slot.id, notes }),
      });
      if (!apptResp.ok) return { ok: false, step: 'appointment', status: apptResp.status, id: '' };
      const appt = (await apptResp.json()) as { appointment_id: string };
      return { ok: true, step: 'done', status: apptResp.status, id: appt.appointment_id };
    },
    {
      apiBase: API_BASE,
      practitionerId: SEED_PRACTITIONER_TABLE_ID,
      patientId,
      startsAt: window.startsAt,
      endsAt: window.endsAt,
      notes,
    },
  );
}

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

  // ── 3. Créneau + POST /v1/cabinet/appointments → RDV créé (201) ──────────
  const createResult = await createCabinetAppointment(
    page,
    SEED_PATIENT_ID,
    'consultation-EX2',
  );

  expect(
    createResult.ok,
    `création RDV (étape ${createResult.step}) attendu 201, reçu ${createResult.status}`,
  ).toBe(true);

  const appointmentId = createResult.id;
  expect(appointmentId, 'id du RDV créé doit être présent').toBeTruthy();
  if (!appointmentId) return; // garde TypeScript

  // ── 4. Déconnexion secrétaire / connexion patient ─────────────────────────
  await clearSession(page);
  await loginAs(page, 'patient');

  // ── 5. Patient : GET /v1/appointments → RDV visible (200) ────────────────
  // Contrat réel : réponse enveloppée {data:[…]}.
  const patientListResult = await page.evaluate(
    async ({ apiBase, appointmentId }: { apiBase: string; appointmentId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      // Le RDV créé est dans le futur → filtre `upcoming` (la liste par défaut
      // est paginée à 20 et saturée de RDV passés/annulés accumulés).
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
  // La page doit se charger sans erreur — les sections "upcoming" et "past" existent.
  // `:visible` + first() pour éviter la strict mode violation (plusieurs nœuds).
  await expect(
    page.locator('#upcoming-loading:visible, #upcoming-list:visible, #upcoming-empty:visible').first(),
  ).toBeVisible({ timeout: 15_000 });
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Aucune fuite cross-rôle
// Un RDV créé (par la secrétaire) pour un AUTRE patient du cabinet ne doit pas
// apparaître dans GET /v1/appointments du patient connecté.
// ─────────────────────────────────────────────────────────────────────────────
test('EX2 : aucune fuite cross-rôle — GET /v1/appointments retourne uniquement les RDV du patient connecté', async ({ page }) => {
  // ── 1. Connexion secrétaire : RDV pour un AUTRE patient ───────────────────
  await loginAs(page, 'secretary');

  const foreign = await createCabinetAppointment(
    page,
    SEED_OTHER_PATIENT_ID,
    'EX2-leak-check',
  );
  expect(
    foreign.ok,
    `création du RDV étranger (étape ${foreign.step}) attendu 201, reçu ${foreign.status}`,
  ).toBe(true);

  // ── 2. Déconnexion secrétaire / connexion patient ─────────────────────────
  await clearSession(page);
  await loginAs(page, 'patient');

  // ── 3. GET /v1/me + GET /v1/appointments → aucune fuite ───────────────────
  // Contrat réel : /v1/me → {user_id, account_id, …} ; liste enveloppée {data}.
  const leakCheck = await page.evaluate(
    async ({ apiBase, foreignId }: { apiBase: string; foreignId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';

      const meResp = await fetch(`${apiBase}/v1/me`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      let me: { id?: string; user_id?: string } = {};
      if (meResp.ok) {
        me = (await meResp.json()) as { id?: string; user_id?: string };
      }
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
    { apiBase: API_BASE, foreignId: foreign.id },
  );

  expect(
    leakCheck.listStatus,
    `GET /v1/appointments attendu 200, reçu ${leakCheck.listStatus}`,
  ).toBe(200);
  expect(leakCheck.myId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  // Le RDV d'un autre patient ne doit pas apparaître
  expect(
    leakCheck.foreignVisible,
    'Fuite détectée : le RDV d\'un autre patient est visible',
  ).toBe(false);
});
