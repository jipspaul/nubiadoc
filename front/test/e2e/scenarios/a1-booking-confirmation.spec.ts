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
import { loginAs, gotoRoute, credentialsFor } from '../fixtures/login';
import { bookAppointment, findOpenSlot } from '../fixtures/cabinet';

const P_EMAIL     = credentialsFor('patient').email;
const P_PASS      = credentialsFor('patient').password;
const S_EMAIL     = credentialsFor('secretariat').email;
const S_PASS      = credentialsFor('secretariat').password;
// Dr Hugo Marin — seed démo (db/seed/seed.sql:97).
const PROVIDER_ID = process.env.DEMO_PROVIDER_ID ?? 'f0000000-0000-0000-0000-0000000000f1';

test.describe('A1 — Booking + confirmation patient/secrétariat', () => {
  test.describe.configure({ mode: 'serial' });

  let pToken: string;
  let sToken: string;
  let appointmentId: string;
  let rdvDate: string; // dérivée du créneau réellement réservé

  test.beforeAll(async () => {
    // Étapes 1 + 3 : logins API en parallèle (browser login dans les tests)
    [pToken, sToken] = await Promise.all([
      loginApi(P_EMAIL, P_PASS),
      loginApi(S_EMAIL, S_PASS),
    ]);

    // Étape 2 : P réserve un RDV — les slots du seed étant régénérés chaque
    // jour, on cherche un créneau open réel plutôt qu'un SLOT_ID figé.
    const { slotId, startsAt } = await findOpenSlot(PROVIDER_ID);
    rdvDate = startsAt.slice(0, 10);
    const motif = `e2e-a1-${Date.now().toString(36)}`;
    appointmentId = await bookAppointment(pToken, {
      providerId: PROVIDER_ID,
      slotId,
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
          const list: { id: string }[] = Array.isArray(body)
            ? body
            : ((body as { data?: { appointment_id: string }[] }).data ?? []);
          return list.filter((a) => a.id === appointmentId);
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
    await gotoRoute(page, 'secretariat', '/agenda');
    // Flutter web n'émet pas de data-testid : on s'appuie sur l'arbre
    // sémantique (nom du patient réservant, affiché sur la tuile agenda).
    await expect(
      page.getByText('Marc Dubois').first(),
      'la tuile agenda du RDV (patient Marc Dubois) doit être visible',
    ).toBeVisible({ timeout: 15_000 });
  });

  // Étape 5 : S clique l'event → "Confirmer" (UI + signal réseau)
  test('Étape 5 — S confirme via UI → POST /cabinet/appointments/:id/confirm 200', async ({ page }) => {
    // S se connecte (contexte isolé de P grâce au page fixture serial)
    await loginAs('secretariat', page);
    await gotoRoute(page, 'secretariat', '/agenda');
    await page.getByText('Marc Dubois').first().click();

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
    await gotoRoute(page, 'patient', '/mes-rdv');
    await expect(
      page.getByText('Confirmé').first(),
      'le statut "Confirmé" doit être visible sur /mes-rdv',
    ).toBeVisible({ timeout: 15_000 });
  });
});
