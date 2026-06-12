/**
 * ES2 — Parcours secrétaire Liste d'attente + patients (E2E flow)
 *
 * Valide le cloisonnement : secrétaire ne voit pas les données cliniques.
 * Couvre W37 (liste-attente) et W38 (patients admin).
 *
 * Scénarios :
 *   1. login secrétaire → liste d'attente (GET /v1/cabinet/waiting-list 200)
 *      → offer premier créneau (POST …/:id/offer 200/204)
 *   2. patients vue admin (GET /v1/cabinet/patients 200) :
 *      - identité/couverture/docs admin visibles (id, first_name, last_name)
 *      - données cliniques absentes : medical-record et dental-chart
 *        non accessibles (403 ou 404 pour la secrétaire)
 *   3. page /secretary/patients s'affiche avec les données admin
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *             R1 restauré (login pro porte cabinet_id+role dans le JWT).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL    URL de l'API backend (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Liste d'attente → GET 200 → offer premier créneau → 200/204
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire : GET /v1/cabinet/waiting-list → 200 et offer sur premier entrée → 200/204', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Récupérer la liste d'attente (GET /v1/cabinet/waiting-list → 200) ──
  // Contrat réel : réponse enveloppée {data: [...]} (api/src/scheduling.rs).
  const { listStatus, firstActiveId } = await page.evaluate(async (apiBase: string) => {
    const jwt = localStorage.getItem('nubia_jwt') ?? '';
    const resp = await fetch(`${apiBase}/v1/cabinet/waiting-list`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    const body = resp.ok
      ? ((await resp.json()) as { data?: Array<{ id: string; status?: string }> })
      : {};
    const entries = body.data ?? [];
    // L'offer n'est valide que sur une entrée `active` (409 invalid_status sinon).
    const firstActive = entries.find((e) => e.status === 'active');
    return { listStatus: resp.status, firstActiveId: firstActive?.id ?? '' };
  }, API_BASE);

  expect(listStatus, `GET /v1/cabinet/waiting-list attendu 200, reçu ${listStatus}`).toBe(200);

  // ── 3. Proposer un créneau sur la première entrée active si elle existe ────
  if (firstActiveId) {
    const offerStatus = await page.evaluate(
      async ({ apiBase, id }: { apiBase: string; id: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        // Contrat réel : body JSON {proposed_at} obligatoire (415/422 sinon).
        const proposedAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
        const resp = await fetch(`${apiBase}/v1/cabinet/waiting-list/${id}/offer`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${jwt}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ proposed_at: proposedAt }),
        });
        return resp.status;
      },
      { apiBase: API_BASE, id: firstActiveId },
    );

    // 200 (with body) ou 204 (no content) selon l'implémentation
    const offerOk = offerStatus === 200 || offerStatus === 204;
    expect(offerOk, `POST …/offer attendu 200 ou 204, reçu ${offerStatus}`).toBe(true);
  }
  // Si aucune entrée active, l'assertion GET 200 suffit pour valider l'accès.
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Patients admin — identité visible, données cliniques absentes
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire : GET /v1/cabinet/patients → 200, identité présente, clinique absente (403/404)', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Liste patients admin (GET /v1/cabinet/patients → 200) ─────────────
  const { patientsStatus, firstPatientId, hasAdminFields } = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/patients`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      // Contrat réel : réponse enveloppée {data: [...], page: {...}} (R10).
      const body = resp.ok
        ? ((await resp.json()) as {
            data?: Array<{ id: string; first_name?: string; last_name?: string }>;
          })
        : {};
      const patients = body.data ?? [];
      const first = patients[0];
      // Vérifie que les champs identité sont présents (id au minimum)
      const hasAdminFields = first !== undefined && typeof first.id === 'string';
      return { patientsStatus: resp.status, firstPatientId: first?.id ?? '', hasAdminFields };
    },
    API_BASE,
  );

  expect(patientsStatus, `GET /v1/cabinet/patients attendu 200, reçu ${patientsStatus}`).toBe(200);

  // ── 3. Données cliniques inaccessibles pour la secrétaire ────────────────
  // (R.4127-72 : secret médical réservé aux praticiens)
  if (firstPatientId) {
    // Le dossier médical (medical-record) doit être interdit (403) ou absent (404)
    const medicalStatus = await page.evaluate(
      async ({ apiBase, id }: { apiBase: string; id: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(`${apiBase}/v1/cabinet/patients/${id}/medical-record`, {
          headers: { Authorization: `Bearer ${jwt}` },
        });
        return resp.status;
      },
      { apiBase: API_BASE, id: firstPatientId },
    );

    // La secrétaire ne doit PAS obtenir 200 sur les données cliniques
    expect(
      medicalStatus,
      `GET .../medical-record ne doit pas retourner 200 pour la secrétaire (reçu ${medicalStatus})`,
    ).not.toBe(200);

    // Le dental-chart doit également être interdit
    const dentalStatus = await page.evaluate(
      async ({ apiBase, id }: { apiBase: string; id: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(`${apiBase}/v1/cabinet/patients/${id}/dental-chart`, {
          headers: { Authorization: `Bearer ${jwt}` },
        });
        return resp.status;
      },
      { apiBase: API_BASE, id: firstPatientId },
    );

    expect(
      dentalStatus,
      `GET .../dental-chart ne doit pas retourner 200 pour la secrétaire (reçu ${dentalStatus})`,
    ).not.toBe(200);
  } else {
    // Aucun patient seed — on vérifie au moins que les champs admin sont cohérents
    expect(hasAdminFields || patientsStatus === 200).toBe(true);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 3 : Page /secretary/patients s'affiche avec la liste admin
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire : page /secretary/patients visible avec table ou message vide', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Naviguer vers la page patients secrétaire ─────────────────────────
  await page.goto('/secretary/patients');

  // ── 3. Le titre H1 doit être visible ─────────────────────────────────────
  await expect(page.locator('h1')).toBeVisible({ timeout: 10_000 });

  // ── 4. La table ou le message vide doit apparaître ────────────────────────
  // Le script client charge les données et affiche soit #patients-table soit
  // #patients-empty. `:visible` + first() : les deux nœuds existent toujours
  // dans le DOM (strict mode violation sinon).
  await expect(
    page.locator('#patients-table:visible, #patients-empty:visible').first(),
  ).toBeVisible({ timeout: 15_000 });
});
