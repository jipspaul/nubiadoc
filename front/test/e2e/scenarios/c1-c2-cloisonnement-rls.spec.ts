/**
 * C1 — Secrétariat NE PEUT PAS accéder au clinique
 * C2 — RLS multi-patient : Patient A ne voit pas les données de Patient B
 *
 * Si l'un de ces tests fail → P0 critique (fuite clinique actionnable).
 * Créer une issue taggée `prio:P0` + `type:security`.
 *
 * Refs : front/docs/e2e-scenarios.md §C1 + §C2 — docs/07-conformite.md
 */

import { test, expect, type Page } from '@playwright/test';
import { loginApi, authedFetch } from '../fixtures/helpers';

const S_URL = process.env.SECRETARIAT_BASE_URL ?? 'http://localhost:4201';

const S_EMAIL = process.env.CRED_SECRETARIAT_EMAIL ?? 'secretariat@nubia-demo.fr';
const S_PASS = process.env.CRED_SECRETARIAT_PASSWORD ?? 'demo-pass';
const P1_EMAIL = process.env.CRED_PATIENT_EMAIL ?? 'patient1@nubia-demo.fr';
const P1_PASS = process.env.CRED_PATIENT_PASSWORD ?? 'demo-pass';
const P2_EMAIL = process.env.CRED_PATIENT2_EMAIL ?? 'patient2@nubia-demo.fr';
const P2_PASS = process.env.CRED_PATIENT2_PASSWORD ?? 'demo-pass';

const PATIENT_ID = process.env.DEMO_PATIENT_ID ?? 'demo-patient-001';
const CONSULT_ID = process.env.DEMO_CONSULTATION_ID ?? 'demo-consult-001';
const PROVIDER_ID = process.env.DEMO_PROVIDER_ID ?? 'demo-provider-001';
const SLOT_ID = process.env.DEMO_SLOT_ID ?? 'demo-slot-001';

async function secretariatBrowserLogin(page: Page): Promise<void> {
  await page.goto(`${S_URL}/login`);
  await page.getByLabel('Email').fill(S_EMAIL);
  await page.getByLabel('Mot de passe').fill(S_PASS);
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.waitForURL(`${S_URL}/**`, { timeout: 15_000 });
}

// ---------------------------------------------------------------------------
// C1 — Secrétariat NE PEUT PAS accéder au clinique
// ---------------------------------------------------------------------------

test.describe('C1 — Cloisonnement clinique (secrétariat)', () => {
  let sToken: string;

  test.beforeAll(async () => {
    sToken = await loginApi(S_EMAIL, S_PASS);
  });

  test('GET /cabinet/patients/:id/notes → exactement 403 Forbidden', async () => {
    const res = await authedFetch(sToken, `/cabinet/patients/${PATIENT_ID}/notes`);
    expect(
      res.status,
      `Attendu 403, obtenu ${res.status} — fuite clinique possible`,
    ).toBe(403);
  });

  test('GET /cabinet/consultations/:id → exactement 403 Forbidden', async () => {
    const res = await authedFetch(sToken, `/cabinet/consultations/${CONSULT_ID}`);
    expect(
      res.status,
      `Attendu 403, obtenu ${res.status} — fuite clinique possible`,
    ).toBe(403);
  });

  test('UI /patients/:id — onglet "Notes cliniques" absent du DOM', async ({ page }) => {
    await secretariatBrowserLogin(page);
    await page.goto(`${S_URL}/patients/${PATIENT_ID}`);
    await page.waitForLoadState('networkidle');

    await expect(
      page.getByText('Notes cliniques', { exact: true }),
      '"Notes cliniques" ne doit pas exister dans le DOM — ni visible, ni hidden',
    ).toHaveCount(0);
  });
});

// ---------------------------------------------------------------------------
// C2 — RLS multi-patient (isolation des données entre patients)
// ---------------------------------------------------------------------------

test.describe('C2 — RLS multi-patient', () => {
  let p1Token: string;
  let p2Token: string;
  let appointmentX: string;

  test.beforeAll(async () => {
    [p1Token, p2Token] = await Promise.all([
      loginApi(P1_EMAIL, P1_PASS),
      loginApi(P2_EMAIL, P2_PASS),
    ]);

    // P1 réserve un RDV et capture appointment_id=X
    const bookRes = await authedFetch(p1Token, '/appointments', {
      method: 'POST',
      body: JSON.stringify({
        provider_id: PROVIDER_ID,
        slot_id: SLOT_ID,
        motif: 'e2e-c2-rls-test',
      }),
    });
    if (!bookRes.ok) {
      throw new Error(`P1 booking échoué: HTTP ${bookRes.status}`);
    }
    const booked = await bookRes.json();
    appointmentX = booked.appointment_id as string;
  });

  test('P2 GET /appointments ne contient pas le RDV X de P1', async () => {
    const res = await authedFetch(p2Token, '/appointments');
    expect(res.status).toBe(200);
    const body = await res.json();
    const list: { appointment_id: string }[] = Array.isArray(body)
      ? body
      : (body.data ?? []);
    expect(
      list.map((a) => a.appointment_id),
      `Le RDV ${appointmentX} de P1 ne doit pas apparaître dans la liste de P2`,
    ).not.toContain(appointmentX);
  });

  test('P2 GET /appointments/:X direct → 404 Not Found (pas 403)', async () => {
    const res = await authedFetch(p2Token, `/appointments/${appointmentX}`);
    expect(
      res.status,
      `Attendu 404 (pas 403) — éviter info-leak sur l'existence du RDV de P1`,
    ).toBe(404);
  });

  test('P2 GET /documents ne contient aucun document de P1', async () => {
    const [p1Res, p2Res] = await Promise.all([
      authedFetch(p1Token, '/documents'),
      authedFetch(p2Token, '/documents'),
    ]);
    expect(p1Res.status).toBe(200);
    expect(p2Res.status).toBe(200);

    const p1Body = await p1Res.json();
    const p2Body = await p2Res.json();
    const p1Ids = new Set<string>(
      (Array.isArray(p1Body) ? p1Body : (p1Body.data ?? [])).map(
        (d: { document_id: string }) => d.document_id,
      ),
    );
    const p2Ids: string[] = (Array.isArray(p2Body) ? p2Body : (p2Body.data ?? [])).map(
      (d: { document_id: string }) => d.document_id,
    );

    for (const id of p2Ids) {
      expect(
        p1Ids.has(id),
        `Document ${id} visible par P2 appartient à P1 — fuite RLS`,
      ).toBe(false);
    }
  });
});
