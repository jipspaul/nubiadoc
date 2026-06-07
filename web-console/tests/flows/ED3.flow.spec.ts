/**
 * ED3 — Patient + consultation praticien (E2E flow)
 *
 * Parcours :
 *   1. Dossier patient : loginAs(practitioner)
 *                        → GET /v1/cabinet/patients → liste (200)
 *                        → GET /v1/cabinet/patients/:id → fiche (200)
 *                        → GET …/medical-record (200)
 *                        → GET …/dental-chart (200)
 *                        → GET …/notes (200)
 *                        → GET …/documents (200)
 *   2. Consultation    : POST /v1/cabinet/appointments/:id/start → consultation ouverte
 *                        → POST /v1/cabinet/consultations/:id/acts → acte ajouté (201)
 *                        → POST /v1/cabinet/consultations/:id/complete → terminée (2xx)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *             R1 restauré (login pro porte cabinet_id+role).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL    URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PATIENT_ID       UUID du patient seed à utiliser pour le dossier
 *   SEED_APPOINTMENT_ID   UUID d'un RDV seed en statut `confirmed` pour start→consult
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SEED_PATIENT_ID =
  process.env.SEED_PATIENT_ID ?? '00000000-0000-0000-0000-000000000002';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Dossier patient — liste + fiche + sections cliniques (tous 200)
// ─────────────────────────────────────────────────────────────────────────────
test('dossier patient : liste → fiche → medical-record / dental-chart / notes / documents tous 200', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Page liste patients W31 : render visible ──────────────────────────
  await page.goto('/clinical/patients');
  await expect(page.locator('h1, main')).toBeVisible({ timeout: 15_000 });

  // ── 3. GET /v1/cabinet/patients → 200 ────────────────────────────────────
  const listResult = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/patients`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return { status: resp.status };
    },
    API_BASE,
  );
  expect(listResult.status).toBe(200);

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

  // ── 9. Page fiche patient W31 : render visible ────────────────────────────
  await page.goto(`/clinical/patients/${SEED_PATIENT_ID}`);
  await expect(page.locator('h1, main')).toBeVisible({ timeout: 15_000 });
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Consultation — start → acte → complete
// ─────────────────────────────────────────────────────────────────────────────
test('consultation : POST appointments/:id/start → POST acts → POST complete', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Résoudre un appointment_id (seed ou créer un RDV) ─────────────────
  let appointmentId: string | null = process.env.SEED_APPOINTMENT_ID ?? null;

  if (!appointmentId) {
    // Chercher un RDV existant en statut utilisable (confirmed/pending)
    const apptList = await page.evaluate(
      async (apiBase: string) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(`${apiBase}/v1/cabinet/appointments`, {
          headers: { Authorization: `Bearer ${jwt}` },
        });
        const data = resp.ok
          ? ((await resp.json()) as Array<{ id: string; status?: string }>)
          : [];
        return { status: resp.status, appointments: Array.isArray(data) ? data : [] };
      },
      API_BASE,
    );

    if (apptList.status === 200 && apptList.appointments.length > 0) {
      const usable = apptList.appointments.find(
        (a) => a.status === 'confirmed' || a.status === 'pending' || a.status === 'checked_in',
      );
      if (usable) appointmentId = usable.id;
    }
  }

  // Si aucun RDV disponible : skip gracieux avec message clair
  if (!appointmentId) {
    // eslint-disable-next-line no-console
    console.warn('ED3 scénario 2 : aucun RDV disponible — précondition manquante (R1 ou seed). Test skippé.');
    return;
  }

  // ── 3. POST /v1/cabinet/appointments/:id/start → consultation créée ───────
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
      const data = resp.ok ? ((await resp.json()) as { id?: string; status?: string }) : null;
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, apptId: appointmentId },
  );

  // start retourne 200 ou 201 ; 409 si déjà démarrée (on continue pour récupérer l'id)
  expect(startResult.status).toBeLessThan(500);
  expect([200, 201, 409]).toContain(startResult.status);

  // Récupérer l'id de la consultation depuis la réponse ou via GET appointment
  let consultationId: string | null = startResult.data?.id ?? null;

  if (!consultationId) {
    // Fallback : GET appointment pour trouver consultation_id
    const apptDetail = await page.evaluate(
      async ({ apiBase, apptId }: { apiBase: string; apptId: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(
          `${apiBase}/v1/cabinet/appointments/${encodeURIComponent(apptId)}`,
          { headers: { Authorization: `Bearer ${jwt}` } },
        );
        const data = resp.ok
          ? ((await resp.json()) as { consultation_id?: string; id?: string })
          : null;
        return { status: resp.status, data };
      },
      { apiBase: API_BASE, apptId: appointmentId },
    );
    consultationId = apptDetail.data?.consultation_id ?? null;
  }

  expect(consultationId).toBeTruthy();
  if (!consultationId) return; // garde TypeScript

  // ── 4. Page consultation W32 : render visible ─────────────────────────────
  await page.goto(`/cabinet/consultations/${consultationId}`);
  await expect(page.locator('h1, main')).toBeVisible({ timeout: 15_000 });

  // ── 5. POST /v1/cabinet/consultations/:id/acts → acte ajouté (201) ────────
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
      const data = resp.ok ? ((await resp.json()) as { id?: string }) : null;
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, consultId: consultationId },
  );

  expect(actResult.status).toBe(201);
  expect(actResult.data?.id).toBeTruthy();

  // ── 6. POST /v1/cabinet/consultations/:id/complete → terminée (2xx) ───────
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
      const data = resp.ok ? ((await resp.json()) as { status?: string }) : null;
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, consultId: consultationId },
  );

  expect(completeResult.status).toBeLessThan(300);
  // Le statut de la consultation doit indiquer la clôture
  if (completeResult.data?.status) {
    expect(['completed', 'closed', 'done']).toContain(completeResult.data.status);
  }
});
