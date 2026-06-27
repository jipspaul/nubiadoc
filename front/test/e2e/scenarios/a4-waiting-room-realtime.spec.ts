/**
 * A4 — Waiting room temps réel (P→S→D→P)
 *
 * Canaux WS :
 *   waiting_room              (pro)     → events: checked_in, queue_updated, patient_called
 *   patient_queue:{appointment_id}      → events: your_turn
 * Si latence WS > 2s → console.warn (pas fail). Timeout dur à 3.5s.
 * Idempotence : bookAndConfirmAppointment crée un RDV frais à chaque run.
 *
 * Refs : front/docs/e2e-scenarios.md §A4
 *        docs/12-api-reference.md §20
 */

import { test, expect, type BrowserContext, type Page } from '@playwright/test';
import { loginApi, authedFetch, bookAndConfirmAppointment } from '../fixtures/helpers';

const WS_BASE = (process.env.WS_BASE_URL ?? 'ws://localhost:8080') + '/v1/ws';
const P_EMAIL = process.env.CRED_PATIENT_EMAIL ?? 'patient1@nubia-demo.fr';
const P_PASS = process.env.CRED_PATIENT_PASSWORD ?? 'demo-pass';
const S_EMAIL = process.env.CRED_SECRETARIAT_EMAIL ?? 'secretariat@nubia-demo.fr';
const S_PASS = process.env.CRED_SECRETARIAT_PASSWORD ?? 'demo-pass';
const D_EMAIL = process.env.CRED_PRATICIEN_EMAIL ?? 'praticien@nubia-demo.fr';
const D_PASS = process.env.CRED_PRATICIEN_PASSWORD ?? 'demo-pass';
const PROVIDER_ID = process.env.DEMO_PROVIDER_ID ?? 'demo-provider-001';
// Doit correspondre à un créneau du jour J dans l'environnement de démo.
const TODAY_SLOT_ID = process.env.DEMO_TODAY_SLOT_ID ?? 'demo-slot-today-001';

const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * Ouvre un WebSocket dans une page dédiée, souscrit au channel,
 * et résout avec la latence (ms) dès que l'event arrive, ou null si
 * le timeout de 3.5s est atteint. Même pattern que D3.
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

test.describe('A4 — Waiting room temps réel', () => {
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
    appointmentId = await bookAndConfirmAppointment(pToken, sToken, PROVIDER_ID, TODAY_SLOT_ID);
  });

  test('Étapes 1-2 : P checkin → S reçoit checked_in sur waiting_room en ≤2s', async ({ context }) => {
    const ws = await subscribeWs(context, sToken, 'waiting_room', 'checked_in');
    await wait(300); // laisse le WS s'établir côté browser

    const checkinRes = await authedFetch(pToken, `/appointments/${appointmentId}/checkin`, {
      method: 'POST',
    });
    expect(checkinRes.status, 'POST /appointments/:id/checkin → 200').toBe(200);

    const latencyMs = await ws.promise;
    await ws.page.close();
    expect(latencyMs, 'WS event checked_in attendu côté S (waiting_room)').not.toBeNull();
    if (latencyMs !== null && latencyMs > 2000)
      console.warn(`[A4] WS S←P checkin latence ${latencyMs}ms > 2s`);
  });

  test('Étapes 3-4 : D call-next → P reçoit your_turn sur patient_queue:{id} en ≤2s', async ({ context }) => {
    const channel = `patient_queue:${appointmentId}`;
    const ws = await subscribeWs(context, pToken, channel, 'your_turn');
    await wait(300);

    const callRes = await authedFetch(dToken, '/cabinet/waiting-room/call-next', {
      method: 'POST',
    });
    expect(callRes.status, 'POST /cabinet/waiting-room/call-next → 200').toBe(200);

    const latencyMs = await ws.promise;
    await ws.page.close();
    expect(latencyMs, 'WS event your_turn attendu côté P (patient_queue)').not.toBeNull();
    if (latencyMs !== null && latencyMs > 2000)
      console.warn(`[A4] WS P←D call-next latence ${latencyMs}ms > 2s`);
  });
});
