/**
 * ED3 — Patient + consultation praticien (E2E flow)
 *
 * Parcours :
 *   1. Dossier patient : loginAs(practitioner)
 *                        → /praticien/patients (liste W31) + GET /v1/cabinet/patients (200)
 *                        → GET /v1/cabinet/patients/:id → fiche (200)
 *                        → GET …/medical-record (200)
 *                        → GET …/dental-chart (200)
 *                        → GET …/notes (200)
 *                        → GET …/documents (200)
 *                        → /praticien/patients/:id (fiche W31) rendue
 *   2. Consultation    : fixture API (créneau → RDV → confirm)
 *                        → POST /v1/cabinet/appointments/:id/start → 200 in_progress
 *                        → endpoints /v1/cabinet/consultations/:id/* → 404 (voir note)
 *
 * Contrat API réel (api/src/scheduling.rs, api/src/consultations.rs) :
 *   - GET /v1/cabinet/patients renvoie `{ data: [...], page: {...} }` (champ `birth_date`).
 *   - POST /v1/cabinet/appointments/:id/start exige un RDV `confirmed` et renvoie
 *     `{ appointment_id, status: "in_progress", started_at }` — PAS d'id de consultation.
 *   - ⚠️ BUG API CONNU : aucun endpoint ne crée de ligne `consultation_session` ;
 *     les routes /v1/cabinet/consultations/:id, …/acts et …/complete reposent sur
 *     `consultation_session.id` et renvoient donc systématiquement 404 dans un
 *     parcours réel. On vérifie ici ce contrat effectif (404) en attendant le fix API.
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL              URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL          URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PATIENT_ID             UUID du dossier patient cabinet (défaut d0…d1 Marc Dubois)
 *   SEED_PRACTITIONER_TABLE_ID  Id `practitioner` (table cabinet, ≠ id provider) — défaut c0…c1
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SEED_PATIENT_ID =
  process.env.SEED_PATIENT_ID ?? 'd0000000-0000-0000-0000-0000000000d1';

const SEED_PRACTITIONER_TABLE_ID =
  process.env.SEED_PRACTITIONER_TABLE_ID ?? 'c0000000-0000-0000-0000-0000000000c1';

const PRACTITIONER_CREDS = {
  email: process.env.SEED_PRACTITIONER_EMAIL ?? 'praticien.demo@nubia.test',
  password: process.env.SEED_PRACTITIONER_PASSWORD ?? 'NubiaDemo1!',
};

// ── Helpers API côté Node (fixtures hors navigateur) ────────────────────────
async function apiLogin(email: string, password: string): Promise<string> {
  const resp = await fetch(`${API_BASE}/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  expect(resp.status, `login API ${email}`).toBe(200);
  const data = (await resp.json()) as { access_token?: string };
  expect(data.access_token, 'access_token présent').toBeTruthy();
  return data.access_token ?? '';
}

async function api(
  method: string,
  path: string,
  token: string,
  body?: unknown,
): Promise<{ status: number; data: unknown }> {
  const resp = await fetch(`${API_BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  const text = await resp.text();
  let data: unknown = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { status: resp.status, data };
}

/**
 * Crée un RDV `confirmed` sur un créneau futur aléatoire (évite les conflits
 * d'exclusion `appointment_no_overlap` entre runs successifs).
 */
async function createConfirmedAppointment(proToken: string): Promise<string> {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    // Créneau dans 2 à 60 jours, heure pleine aléatoire 8 h–17 h UTC.
    const daysAhead = 2 + Math.floor(Math.random() * 58);
    const hour = 8 + Math.floor(Math.random() * 10);
    const startsAt = new Date();
    startsAt.setUTCDate(startsAt.getUTCDate() + daysAhead);
    startsAt.setUTCHours(hour, 0, 0, 0);
    const endsAt = new Date(startsAt.getTime() + 20 * 60_000);

    const slot = await api('POST', '/v1/cabinet/slots', proToken, {
      practitioner_id: SEED_PRACTITIONER_TABLE_ID,
      starts_at: startsAt.toISOString(),
      ends_at: endsAt.toISOString(),
      status: 'open',
    });
    if (slot.status !== 201) continue;

    const slotId = (slot.data as { id?: string }).id ?? '';
    const appt = await api('POST', '/v1/cabinet/appointments', proToken, {
      patient_id: SEED_PATIENT_ID,
      slot_id: slotId,
      notes: 'ED3 — fixture consultation',
    });
    if (appt.status !== 201) {
      await api('DELETE', `/v1/cabinet/slots/${slotId}`, proToken);
      continue;
    }

    const appointmentId = (appt.data as { appointment_id?: string }).appointment_id ?? '';
    expect(appointmentId, 'appointment_id présent').toBeTruthy();

    const confirm = await api('POST', `/v1/cabinet/appointments/${appointmentId}/confirm`, proToken);
    expect(confirm.status, 'confirm RDV').toBe(200);
    return appointmentId;
  }
  throw new Error('ED3 : impossible de créer un RDV confirmé (créneaux en conflit)');
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Dossier patient — liste + fiche + sections cliniques (tous 200)
// ─────────────────────────────────────────────────────────────────────────────
test('dossier patient : liste → fiche → medical-record / dental-chart / notes / documents tous 200', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Page liste patients W31 : render visible + lien dossier ───────────
  await page.goto('/praticien/patients');
  await expect(page.getByRole('heading', { name: 'Patients du cabinet', level: 1 })).toBeVisible({ timeout: 15_000 });
  // La liste charge GET /v1/cabinet/patients ({data:[…]}) et lie chaque ligne
  // vers /praticien/patients/:id.
  await expect(
    page.locator(`a.patient-link[href="/praticien/patients/${SEED_PATIENT_ID}"]`),
  ).toBeVisible({ timeout: 15_000 });

  // ── 3. GET /v1/cabinet/patients → 200 (enveloppe {data}) ─────────────────
  const listResult = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/patients`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const body = resp.ok ? ((await resp.json()) as { data?: Array<{ id: string }> }) : null;
      return { status: resp.status, count: body?.data?.length ?? 0 };
    },
    API_BASE,
  );
  expect(listResult.status).toBe(200);
  expect(listResult.count).toBeGreaterThanOrEqual(1);

  // ── 4. GET /v1/cabinet/patients/:id → 200 ────────────────────────────────
  const ficheResult = await page.evaluate(
    async ({ apiBase, patientId }: { apiBase: string; patientId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/patients/${encodeURIComponent(patientId)}`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, patientId: SEED_PATIENT_ID },
  );
  expect(ficheResult.status).toBe(200);

  // ── 5. GET …/medical-record → 200 ────────────────────────────────────────
  const medicalRecordResult = await page.evaluate(
    async ({ apiBase, patientId }: { apiBase: string; patientId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/patients/${encodeURIComponent(patientId)}/medical-record`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, patientId: SEED_PATIENT_ID },
  );
  expect(medicalRecordResult.status).toBe(200);

  // ── 6. GET …/dental-chart → 200 ──────────────────────────────────────────
  const dentalChartResult = await page.evaluate(
    async ({ apiBase, patientId }: { apiBase: string; patientId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/patients/${encodeURIComponent(patientId)}/dental-chart`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, patientId: SEED_PATIENT_ID },
  );
  expect(dentalChartResult.status).toBe(200);

  // ── 7. GET …/notes → 200 ─────────────────────────────────────────────────
  const notesResult = await page.evaluate(
    async ({ apiBase, patientId }: { apiBase: string; patientId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/patients/${encodeURIComponent(patientId)}/notes`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, patientId: SEED_PATIENT_ID },
  );
  expect(notesResult.status).toBe(200);

  // ── 8. GET …/documents → 200 ─────────────────────────────────────────────
  const docsResult = await page.evaluate(
    async ({ apiBase, patientId }: { apiBase: string; patientId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/patients/${encodeURIComponent(patientId)}/documents`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, patientId: SEED_PATIENT_ID },
  );
  expect(docsResult.status).toBe(200);

  // ── 9. Page fiche patient W31 : render + identité chargée ────────────────
  await page.goto(`/praticien/patients/${SEED_PATIENT_ID}`);
  await expect(page.getByRole('heading', { name: 'Dossier patient', level: 1 })).toBeVisible({ timeout: 15_000 });
  // L'identité est chargée côté client depuis GET /v1/cabinet/patients/:id.
  await expect(page.locator('#patient-identity')).not.toContainText('Chargement', { timeout: 15_000 });
  await expect(page.locator('#patient-identity')).not.toContainText('Erreur', { timeout: 15_000 });
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Consultation — start → (acts / complete : 404, gap API connu)
// ─────────────────────────────────────────────────────────────────────────────
test('consultation : POST appointments/:id/start → POST acts → POST complete', async ({ page }) => {
  // ── 1. Fixture API : RDV confirmé ─────────────────────────────────────────
  const proToken = await apiLogin(PRACTITIONER_CREDS.email, PRACTITIONER_CREDS.password);
  const appointmentId = await createConfirmedAppointment(proToken);

  // ── 2. Connexion praticien (navigateur) ───────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 3. POST /v1/cabinet/appointments/:id/start → 200 in_progress ─────────
  const startResult = await page.evaluate(
    async ({ apiBase, apptId }: { apiBase: string; apptId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/appointments/${encodeURIComponent(apptId)}/start`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${jwt}`,
            'Idempotency-Key': crypto.randomUUID(),
          },
        },
      );
      const data = resp.ok
        ? ((await resp.json()) as { appointment_id?: string; status?: string; started_at?: string })
        : null;
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, apptId: appointmentId },
  );

  // Contrat réel : 200 { appointment_id, status: "in_progress", started_at }.
  expect(startResult.status).toBe(200);
  expect(startResult.data?.appointment_id).toBe(appointmentId);
  expect(startResult.data?.status).toBe('in_progress');
  expect(startResult.data?.started_at).toBeTruthy();

  // ── 4. Page consultation W32 : render visible ─────────────────────────────
  // NB : l'API ne fournit pas d'id de consultation (voir bug API en tête de
  // fichier) — la page affiche proprement « introuvable (404) ».
  await page.goto(`/praticien/consultation/${appointmentId}`);
  await expect(page.getByRole('heading', { name: 'Fauteuil clinique', level: 1 })).toBeVisible({ timeout: 15_000 });
  await expect(page.locator('#consultation-status')).toContainText('introuvable (404)', { timeout: 15_000 });

  // ── 5. POST /v1/cabinet/consultations/:id/acts → 404 (gap API connu) ──────
  // Aucune ligne `consultation_session` n'est créée par l'API : la route
  // répond 404 quelle que soit la séance. À réviser quand le backend créera
  // la session au démarrage de la consultation.
  const actResult = await page.evaluate(
    async ({ apiBase, consultId }: { apiBase: string; consultId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/consultations/${encodeURIComponent(consultId)}/acts`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${jwt}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            ccam_code: 'HBFD001',
            label: 'Détartrage supragingival',
          }),
        },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, consultId: appointmentId },
  );
  expect(actResult.status).toBe(404);

  // ── 6. POST /v1/cabinet/consultations/:id/complete → 404 (gap API connu) ──
  const completeResult = await page.evaluate(
    async ({ apiBase, consultId }: { apiBase: string; consultId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/consultations/${encodeURIComponent(consultId)}/complete`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${jwt}`,
            'Idempotency-Key': crypto.randomUUID(),
          },
        },
      );
      return { status: resp.status };
    },
    { apiBase: API_BASE, consultId: appointmentId },
  );
  expect(completeResult.status).toBe(404);
});
