/**
 * A1 — Booking + confirmation patient/secrétariat
 *
 * Flux : P login → P book RDV → S login → S voit agenda → S confirme → P voit "confirmé"
 * Idempotent : motif horodaté → 2 runs consécutifs = 2 PASS sans nettoyage.
 *
 * Refs : front/docs/e2e-scenarios.md §A1
 *        docs/12-api-reference.md §3.2 + §13
 */

import { test, expect } from '@playwright/test';
import { loginApi, authedFetch } from '../fixtures/helpers';
import { loginAs, baseUrlFor } from '../fixtures/login';
import { bookAppointment } from '../fixtures/cabinet';

const P_EMAIL     = process.env.CRED_PATIENT_EMAIL       ?? 'patient1@nubia-demo.fr';
const P_PASS      = process.env.CRED_PATIENT_PASSWORD    ?? 'demo-pass';
const S_EMAIL     = process.env.CRED_SECRETARIAT_EMAIL   ?? 'secretariat@nubia-demo.fr';
const S_PASS      = process.env.CRED_SECRETARIAT_PASSWORD ?? 'demo-pass';
const PROVIDER_ID = process.env.DEMO_PROVIDER_ID         ?? 'demo-provider-001';
const SLOT_ID     = process.env.DEMO_SLOT_ID             ?? 'demo-slot-001';

test.describe('A1 — Booking + confirmation patient/secrétariat', () => {
  test.describe.configure({ mode: 'serial' });

  let pToken: string;
  let sToken: string;
  let appointmentId: string;
  const rdvDate = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (today)

  test.beforeAll(async () => {
    // Étapes 1 + 3 : logins API en parallèle (browser login dans les tests)
    [pToken, sToken] = await Promise.all([
      loginApi(P_EMAIL, P_PASS),
      loginApi(S_EMAIL, S_PASS),
    ]);

    // Étape 2 : P réserve un RDV — motif horodaté pour idempotence inter-runs
    const motif = `e2e-a1-${Date.now().toString(36)}`;
    appointmentId = await bookAppointment(pToken, {
      providerId: PROVIDER_ID,
      slotId: SLOT_ID,
      motif,
    });
  });

  // Étape 4 : S voit le RDV dans l'agenda (signal réseau + UI selector)
  test('Étape 4 — S agenda : GET /cabinet/appointments retourne le RDV + selector visible', async ({ page }) => {
    // Signal réseau : RDV présent dans la réponse API
    await expect
      .poll(
        async () => {
          const res = await authedFetch(sToken, `/cabinet/appointments?date=${rdvDate}`);
          if (!res.ok) return [];
          const body = (await res.json()) as unknown;
          const list: { appointment_id: string }[] = Array.isArray(body)
            ? body
            : ((body as { data?: { appointment_id: string }[] }).data ?? []);
          return list.filter((a) => a.appointment_id === appointmentId);
        },
        {
          message: `RDV ${appointmentId} doit apparaître dans GET /cabinet/appointments?date=${rdvDate}`,
          timeout: 10_000,
          intervals: [500, 1000, 2000],
        },
      )
      .toHaveLength(1);

    // UI : S se connecte et vérifie que l'event est visible dans l'agenda
    await loginAs('secretariat', page);
    await page.goto(`${baseUrlFor('secretariat')}/agenda`);
    await expect(
      page.getByTestId(`agenda-event-${appointmentId}`),
      `[data-testid="agenda-event-${appointmentId}"] doit être visible`,
    ).toBeVisible({ timeout: 15_000 });
  });

  // Étape 5 : S clique l'event → "Confirmer" (UI + signal réseau)
  test('Étape 5 — S confirme via UI → POST /cabinet/appointments/:id/confirm 200', async ({ page }) => {
    // S se connecte (contexte isolé de P grâce au page fixture serial)
    await loginAs('secretariat', page);
    await page.goto(`${baseUrlFor('secretariat')}/agenda`);
    await page.getByTestId(`agenda-event-${appointmentId}`).click();

    // Capture la réponse réseau déclenchée par le clic "Confirmer"
    const [confirmRes] = await Promise.all([
      page.waitForResponse(
        (r) =>
          r.url().includes(`/appointments/${appointmentId}/confirm`) &&
          r.request().method() === 'POST',
        { timeout: 10_000 },
      ),
      page.getByRole('button', { name: 'Confirmer' }).click(),
    ]);

    expect(
      confirmRes.status(),
      `POST /v1/cabinet/appointments/${appointmentId}/confirm → 200`,
    ).toBe(200);
    const body = (await confirmRes.json()) as { status: string };
    expect(body.status, 'status → confirmed après confirmation S').toBe('confirmed');
  });

  // Étape 6 : P rafraîchit /mes-rdv → statut "Confirmé" affiché (signal réseau + UI)
  test('Étape 6 — P voit le RDV en statut "Confirmé" sur /mes-rdv', async ({ page }) => {
    // Signal réseau : API retourne status=confirmed côté patient
    const apiRes = await authedFetch(pToken, `/appointments/${appointmentId}`);
    expect(apiRes.status, `GET /v1/appointments/${appointmentId} → 200`).toBe(200);
    const appt = (await apiRes.json()) as { status: string };
    expect(appt.status, 'status API → confirmed').toBe('confirmed');

    // UI : P se connecte, navigue sur /mes-rdv et vérifie le statut "Confirmé"
    await loginAs('patient', page);
    await page.goto(`${baseUrlFor('patient')}/mes-rdv`);
    await expect(
      page.getByTestId(`appointment-status-${appointmentId}`),
      `appointment-status-${appointmentId} doit afficher "Confirmé"`,
    ).toHaveText('Confirmé', { timeout: 15_000 });
  });
});
