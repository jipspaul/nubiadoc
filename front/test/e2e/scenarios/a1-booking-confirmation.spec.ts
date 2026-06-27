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

const P_EMAIL = process.env.CRED_PATIENT_EMAIL ?? 'patient1@nubia-demo.fr';
const P_PASS = process.env.CRED_PATIENT_PASSWORD ?? 'demo-pass';
const S_EMAIL = process.env.CRED_SECRETARIAT_EMAIL ?? 'secretariat@nubia-demo.fr';
const S_PASS = process.env.CRED_SECRETARIAT_PASSWORD ?? 'demo-pass';
const PROVIDER_ID = process.env.DEMO_PROVIDER_ID ?? 'demo-provider-001';
const SLOT_ID = process.env.DEMO_SLOT_ID ?? 'demo-slot-001';

test.describe('A1 — Booking + confirmation patient/secrétariat', () => {
  let pToken: string;
  let sToken: string;
  let appointmentId: string;
  const rdvDate = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (today)

  test.beforeAll(async () => {
    // Étapes 1 + 3 : logins en parallèle
    [pToken, sToken] = await Promise.all([
      loginApi(P_EMAIL, P_PASS),
      loginApi(S_EMAIL, S_PASS),
    ]);

    // Étape 2 : P réserve un RDV — motif horodaté pour garantir l'idempotence inter-runs
    const motif = `e2e-a1-${Date.now().toString(36)}`;
    const bookRes = await authedFetch(pToken, '/appointments', {
      method: 'POST',
      body: JSON.stringify({ provider_id: PROVIDER_ID, slot_id: SLOT_ID, motif }),
    });
    expect(
      bookRes.status,
      `POST /v1/appointments → 201 (obtenu ${bookRes.status})`,
    ).toBe(201);
    const booked = (await bookRes.json()) as { appointment_id: string; status: string };
    appointmentId = booked.appointment_id;
    expect(appointmentId, 'appointment_id retourné dans la réponse 201').toBeTruthy();
  });

  // Étape 4 : S voit le RDV dans l'agenda du jour (status requested)
  test('Étape 4 — S GET /cabinet/appointments?date=... contient le RDV', async () => {
    await expect
      .poll(
        async () => {
          const res = await authedFetch(
            sToken,
            `/cabinet/appointments?date=${rdvDate}`,
          );
          if (!res.ok) return [];
          const body = await res.json();
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
  });

  // Étape 5 : S confirme → requested → confirmed
  test('Étape 5 — S POST /cabinet/appointments/:id/confirm → 200 + status confirmed', async () => {
    const confirmRes = await authedFetch(
      sToken,
      `/cabinet/appointments/${appointmentId}/confirm`,
      { method: 'POST' },
    );
    expect(
      confirmRes.status,
      `POST /v1/cabinet/appointments/${appointmentId}/confirm → 200 (obtenu ${confirmRes.status})`,
    ).toBe(200);
    const body = (await confirmRes.json()) as { status: string };
    expect(body.status, 'status → confirmed après confirmation S').toBe('confirmed');
  });

  // Étape 6 : P consulte /mes-rdv → statut "confirmé"
  test('Étape 6 — P GET /appointments/:id → status confirmed', async () => {
    const res = await authedFetch(pToken, `/appointments/${appointmentId}`);
    expect(res.status, `GET /v1/appointments/${appointmentId} → 200`).toBe(200);
    const appt = (await res.json()) as { status: string };
    expect(appt.status, 'statut RDV côté patient → confirmed').toBe('confirmed');
  });
});
