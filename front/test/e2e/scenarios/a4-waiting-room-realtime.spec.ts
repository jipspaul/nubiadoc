/**
 * A4 — Waiting room temps réel (P→S→D→P)
 *
 * Flux : P checkin → S voit patient dans salle d'attente (WS checked_in) →
 *        D call-next → P reçoit "C'est à vous" (WS patient_queue:{id} your_turn)
 * Latence WS attendue ≤2s. Si >2s : console.warn sans fail.
 * Idempotent : motif horodaté → 2 runs consécutifs = 2 PASS sans nettoyage.
 *
 * Refs : front/docs/e2e-scenarios.md §A4
 *        docs/12-api-reference.md §15, §20
 */

import { test, expect, type BrowserContext, type Page } from '@playwright/test';
import { loginApi, authedFetch } from '../fixtures/helpers';
import { credentialsFor, gotoRoute } from '../fixtures/login';
import { bookAndConfirmAppointment, findOpenSlot } from '../fixtures/cabinet';

const WS_BASE = (process.env.WS_BASE_URL ?? 'ws://localhost:8080') + '/v1/ws';
const P_EMAIL = credentialsFor('patient').email;
const P_PASS = credentialsFor('patient').password;
const S_EMAIL = credentialsFor('secretariat').email;
const S_PASS = credentialsFor('secretariat').password;
const D_EMAIL = credentialsFor('practicien').email;
const D_PASS = credentialsFor('practicien').password;
// Dr Hugo Marin — seed démo (db/seed/seed.sql:97).
const PROVIDER_ID = process.env.DEMO_PROVIDER_ID ?? 'f0000000-0000-0000-0000-0000000000f1';

const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * Ouvre un WebSocket dans une page dédiée, souscrit au channel, et résout
 * avec la latence (ms) dès que l'event arrive, ou null si timeout 3.5s atteint.
 */
async function subscribeWs(
  context: BrowserContext,
  token: string,
  channel: string,
  event: string,
): Promise<{ page: Page; promise: Promise<number | null> }> {
  const wsPage = await context.newPage();
  const promise = wsPage.evaluate(
    ({ wsUrl, token, channel, event }) =>
      new Promise<number | null>((resolve) => {
        const ws = new WebSocket(`${wsUrl}?access_token=${token}`);
        const t0 = performance.now();
        const done = (v: number | null) => { ws.close(); resolve(v); };
        setTimeout(() => done(null), 3500);
        ws.onopen = () => ws.send(JSON.stringify({ op: 'subscribe', channel }));
        ws.onmessage = (e) => {
          const p = JSON.parse(e.data as string) as { channel: string; event: string };
          if (p.channel === channel && p.event === event) done(Math.round(performance.now() - t0));
        };
        ws.onerror = () => done(null);
      }),
    { wsUrl: WS_BASE, token, channel, event },
  );
  return { page: wsPage, promise };
}

test.describe('A4 — Waiting room temps réel (P→S→D→P)', () => {
  test.describe.configure({ mode: 'serial' });

  let pToken: string;
  let sToken: string;
  let dToken: string;
  let appointmentId: string;

  test.beforeAll(async () => {
    [pToken, sToken, dToken] = await Promise.all([
      loginApi(P_EMAIL, P_PASS),
      loginApi(S_EMAIL, S_PASS),
      loginApi(D_EMAIL, D_PASS),
    ]);

    const motif = `e2e-a4-${Date.now().toString(36)}`;
    const { slotId } = await findOpenSlot(PROVIDER_ID);
    appointmentId = await bookAndConfirmAppointment(pToken, sToken, {
      providerId: PROVIDER_ID,
      slotId,
      motif,
    });
  });

  // BLOQUÉ ENV/API : le checkin exige un RDV du jour (409 sinon) or les slots
  // seed du jour ne sont pas garantis à l'heure du run ; et l'event
  // `checked_in` n'est pas publié sur le canal waiting_room par
  // POST /appointments/:id/checkin. À réactiver avec un seed same-day + publish.
  test.fixme('Étapes 1-2 : P checkin → S reçoit checked_in via WS en ≤2s', async ({ context }) => {
    const ws = await subscribeWs(context, sToken, 'waiting_room', 'checked_in');
    await wait(300); // laisse le WS s'établir côté browser

    const checkinRes = await authedFetch(pToken, `/appointments/${appointmentId}/checkin`, {
      method: 'POST',
    });
    expect(
      checkinRes.status,
      `POST /v1/appointments/${appointmentId}/checkin → 200 (obtenu ${checkinRes.status})`,
    ).toBe(200);

    const latencyMs = await ws.promise;
    await ws.page.close();
    expect(latencyMs, 'WS event checked_in attendu côté S (waiting_room)').not.toBeNull();
    if (latencyMs !== null && latencyMs > 2000) {
      console.warn(`[A4] WS S←checked_in latence ${latencyMs}ms > 2s`);
    }
  });

  // BLOQUÉ API : canal `patient_queue:*` absent du hub WS (waiting_room seul).
  test.fixme('Étapes 3-4 : D call-next → P reçoit your_turn via WS en ≤2s', async ({ context }) => {
    const channel = `patient_queue:${appointmentId}`;
    const ws = await subscribeWs(context, pToken, channel, 'your_turn');
    await wait(300); // laisse le WS s'établir côté browser

    const callNextRes = await authedFetch(dToken, '/cabinet/waiting-room/call-next', {
      method: 'POST',
    });
    expect(
      [200, 204],
      `POST /v1/cabinet/waiting-room/call-next → 200/204 (obtenu ${callNextRes.status})`,
    ).toContain(callNextRes.status);

    const latencyMs = await ws.promise;
    await ws.page.close();
    expect(latencyMs, `WS event your_turn attendu côté P (patient_queue:${appointmentId})`).not.toBeNull();
    if (latencyMs !== null && latencyMs > 2000) {
      console.warn(`[A4] WS P←your_turn latence ${latencyMs}ms > 2s`);
    }
  });
});
