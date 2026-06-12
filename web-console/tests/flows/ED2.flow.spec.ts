/**
 * ED2 — Salle d'attente praticien (E2E flow)
 *
 * Parcours :
 *   1. Render : loginAs(practitioner) → GET /praticien/file → page 200, sections visibles
 *   2. Call-next : fixture API (créneau → RDV → confirm → check-in patient)
 *                  GET /v1/cabinet/waiting-room → entrée `checked_in` visible
 *                  POST /v1/cabinet/waiting-room/call-next (via UI) → patient appelé
 *                  → le nombre d'entrées `checked_in` diminue
 *
 * Contrat API réel (api/src/scheduling.rs) :
 *   - GET /v1/cabinet/waiting-room → 200 `{ entries: [{ appointment_id, patient_id, status, checkin_at }] }`
 *     (les RDV `in_progress` non démarrés restent listés — on compte donc les `checked_in`).
 *   - POST /v1/cabinet/waiting-room/call-next → 200 `{ called: false }` si file vide,
 *     sinon `{ called: true, appointment_id, patient_display_name }` (`checked_in → in_progress`).
 *   - Le check-in exige un token patient, un RDV `confirmed` et une fenêtre
 *     `starts_at − 30 min … starts_at + 60 min` (POST /v1/appointments/:id/checkin).
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL              URL de l'app web   (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL          URL de l'API back  (défaut http://localhost:38030)
 *   SEED_PRACTITIONER_TABLE_ID  Id `practitioner` (table cabinet, ≠ id provider) — défaut c0…c1
 *   SEED_PATIENT_ID             Id `patient` (dossier cabinet) — défaut d0…d1 (Marc Dubois)
 *   SEED_PRACTITIONER_EMAIL/_PASSWORD, SEED_PATIENT_EMAIL/_PASSWORD  Comptes seed
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SEED_PRACTITIONER_TABLE_ID =
  process.env.SEED_PRACTITIONER_TABLE_ID ?? 'c0000000-0000-0000-0000-0000000000c1';

const SEED_PATIENT_ID =
  process.env.SEED_PATIENT_ID ?? 'd0000000-0000-0000-0000-0000000000d1';

const PRACTITIONER_CREDS = {
  email: process.env.SEED_PRACTITIONER_EMAIL ?? 'praticien.demo@nubia.test',
  password: process.env.SEED_PRACTITIONER_PASSWORD ?? 'NubiaDemo1!',
};

const PATIENT_CREDS = {
  email: process.env.SEED_PATIENT_EMAIL ?? 'patient.demo@nubia.test',
  password: process.env.SEED_PATIENT_PASSWORD ?? 'NubiaDemo1!',
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
 * Crée un RDV `checked_in` pour aujourd'hui :
 * créneau (practitioner-table id) → RDV → confirm → check-in (token patient).
 * Essaie plusieurs fenêtres horaires pour éviter les conflits d'exclusion
 * (`appointment_no_overlap` / `slot_practitioner_no_overlap`) laissés par
 * d'éventuels runs précédents.
 */
async function createCheckedInAppointment(proToken: string, patientToken: string): Promise<string> {
  // Fenêtre check-in : starts_at ∈ [now − 60 min, now + 30 min].
  const offsetsMin = [3, 9, 15, 21, 27, -10, -16, -22, -28, -34];

  for (const offset of offsetsMin) {
    const startsAt = new Date(Date.now() + offset * 60_000);
    const endsAt = new Date(startsAt.getTime() + 5 * 60_000);

    const slot = await api('POST', '/v1/cabinet/slots', proToken, {
      practitioner_id: SEED_PRACTITIONER_TABLE_ID,
      starts_at: startsAt.toISOString(),
      ends_at: endsAt.toISOString(),
      status: 'open',
    });
    if (slot.status !== 201) continue; // créneau en conflit → fenêtre suivante

    const slotId = (slot.data as { id?: string }).id ?? '';
    const appt = await api('POST', '/v1/cabinet/appointments', proToken, {
      patient_id: SEED_PATIENT_ID,
      slot_id: slotId,
      notes: 'ED2 — fixture salle d’attente',
    });
    if (appt.status !== 201) {
      // RDV en conflit (409 slot_taken) → on supprime le créneau et on réessaie.
      await api('DELETE', `/v1/cabinet/slots/${slotId}`, proToken);
      continue;
    }

    const appointmentId = (appt.data as { appointment_id?: string }).appointment_id ?? '';
    expect(appointmentId, 'appointment_id présent').toBeTruthy();

    const confirm = await api('POST', `/v1/cabinet/appointments/${appointmentId}/confirm`, proToken);
    expect(confirm.status, 'confirm RDV').toBe(200);

    const checkin = await api('POST', `/v1/appointments/${appointmentId}/checkin`, patientToken, {
      method: 'manual',
    });
    expect(checkin.status, 'check-in patient').toBe(200);
    expect((checkin.data as { status?: string }).status).toBe('checked_in');

    return appointmentId;
  }

  throw new Error('ED2 : impossible de créer un RDV checked_in (toutes les fenêtres en conflit)');
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Render — login praticien → /praticien/file s'affiche (200)
// ─────────────────────────────────────────────────────────────────────────────
test('render : loginAs(practitioner) → /praticien/file affiche les sections (200)', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Navigation vers la page W30 ───────────────────────────────────────
  await page.goto('/praticien/file');

  // ── 3. Page correctement rendue (pas de redirect 401/403) ────────────────
  await expect(page.getByRole('heading', { name: "Salle d'attente", level: 1 })).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole('heading', { name: 'File d\'attente', level: 2 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Appeler le suivant', level: 2 })).toBeVisible();
  await expect(page.getByRole('button', { name: /appeler le patient suivant/i })).toBeVisible();

  // ── 4. GET /v1/cabinet/waiting-room → 200 (via API directe) ──────────────
  const roomResult = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/waiting-room`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return { status: resp.status };
    },
    API_BASE,
  );
  expect(roomResult.status).toBe(200);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Call-next — POST call-next → patient retiré de la file
// ─────────────────────────────────────────────────────────────────────────────
test('call-next : POST /v1/cabinet/waiting-room/call-next → patient retiré (polling mis à jour)', async ({ page }) => {
  // ── 1. Fixture API : RDV checked_in aujourd'hui ───────────────────────────
  const proToken = await apiLogin(PRACTITIONER_CREDS.email, PRACTITIONER_CREDS.password);
  const patientToken = await apiLogin(PATIENT_CREDS.email, PATIENT_CREDS.password);
  await createCheckedInAppointment(proToken, patientToken);

  // ── 2. Lire la file avant l'appel (entrées checked_in) ───────────────────
  // NB : les entrées restent listées en `in_progress` après call-next
  // (started_at non posé) — seul le statut change. On compte les `checked_in`.
  const before = await api('GET', '/v1/cabinet/waiting-room', proToken);
  expect(before.status).toBe(200);
  const beforeEntries = (before.data as { entries?: Array<{ status?: string }> }).entries ?? [];
  const beforeCheckedIn = beforeEntries.filter((e) => e.status === 'checked_in').length;
  expect(beforeCheckedIn).toBeGreaterThanOrEqual(1);

  // ── 3. UI : la file affiche le patient ────────────────────────────────────
  await loginAs(page, 'practitioner');
  await page.goto('/praticien/file');
  await expect(page.locator('#queue-content')).toBeVisible({ timeout: 15_000 });
  await expect(page.locator('#queue-tbody tr')).not.toHaveCount(0, { timeout: 15_000 });

  // ── 4. POST call-next via le bouton UI ───────────────────────────────────
  await page.getByRole('button', { name: /appeler le patient suivant/i }).click();
  await expect(page.locator('#call-next-patient')).toBeVisible({ timeout: 15_000 });
  await expect(page.locator('#call-next-patient')).toContainText(/Patient appelé/, { timeout: 15_000 });

  // ── 5. La file a diminué d'au moins un checked_in ─────────────────────────
  const after = await api('GET', '/v1/cabinet/waiting-room', proToken);
  expect(after.status).toBe(200);
  const afterEntries = (after.data as { entries?: Array<{ status?: string }> }).entries ?? [];
  const afterCheckedIn = afterEntries.filter((e) => e.status === 'checked_in').length;
  expect(afterCheckedIn).toBeLessThan(beforeCheckedIn);

  // ── 6. La page UI reste fonctionnelle après l'appel (polling) ─────────────
  await expect(page.locator('#queue-content')).toBeVisible({ timeout: 15_000 });
});
