/**
 * D3 — Messagerie cabinet temps réel (P↔S, channel WS conversation)
 *
 * Canal WS : conversation:{id} — events message_created, read
 * Si latence WS > 2s → console.warn (pas fail). Timeout dur à 3.5s.
 * Idempotence : POST /conversations crée une conversation fraîche par run.
 *
 * Refs : front/docs/e2e-scenarios.md §D3
 *        docs/12-api-reference.md §9, §18, §20
 */

import { test, expect, type BrowserContext, type Page } from '@playwright/test';
import { loginApi, authedFetch } from '../fixtures/helpers';

const WS_BASE = (process.env.WS_BASE_URL ?? 'ws://localhost:8080') + '/v1/ws';
const P_EMAIL = process.env.CRED_PATIENT_EMAIL ?? 'patient1@nubia-demo.fr';
const P_PASS = process.env.CRED_PATIENT_PASSWORD ?? 'demo-pass';
const S_EMAIL = process.env.CRED_SECRETARIAT_EMAIL ?? 'secretariat@nubia-demo.fr';
const S_PASS = process.env.CRED_SECRETARIAT_PASSWORD ?? 'demo-pass';
const CABINET_ID = process.env.DEMO_CABINET_ID ?? 'demo-cabinet-001';

const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * Ouvre un WebSocket dans une page dédiée (hors page principale du test),
 * souscrit au channel, et résout avec la latence (ms) dès que l'event arrive,
 * ou null si le timeout de 3.5s est atteint.
 * La page WS est séparée pour permettre l'exécution concurrente avec l'action API.
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

test.describe('D3 — Messagerie cabinet temps réel', () => {
  let pToken: string;
  let sToken: string;
  let conversationId: string;

  test.beforeAll(async () => {
    [pToken, sToken] = await Promise.all([loginApi(P_EMAIL, P_PASS), loginApi(S_EMAIL, S_PASS)]);
    const res = await authedFetch(pToken, '/conversations', {
      method: 'POST',
      body: JSON.stringify({ cabinet_id: CABINET_ID }),
    });
    if (!res.ok) throw new Error(`POST /conversations échoué: HTTP ${res.status}`);
    conversationId = ((await res.json()) as { conversation_id: string }).conversation_id;
  });

  test('Étapes 1-2 : P envoie → S reçoit via WS en ≤2s', async ({ context }) => {
    const channel = `conversation:${conversationId}`;
    const ws = await subscribeWs(context, sToken, channel, 'message_created');
    await wait(300); // laisse le WS s'établir côté browser

    const sendRes = await authedFetch(pToken, `/conversations/${conversationId}/messages`, {
      method: 'POST',
      body: JSON.stringify({ body: `e2e-d3-p-${Date.now().toString(36)}` }),
    });
    expect(sendRes.status, 'POST /conversations/:id/messages → 201').toBe(201);

    const latencyMs = await ws.promise;
    await ws.page.close();
    expect(latencyMs, 'WS event message_created attendu côté S').not.toBeNull();
    if (latencyMs !== null && latencyMs > 2000) console.warn(`[D3] WS S←P latence ${latencyMs}ms > 2s`);
  });

  test('Étapes 3-4 : S répond → P reçoit via WS en ≤2s', async ({ context }) => {
    const channel = `conversation:${conversationId}`;
    const ws = await subscribeWs(context, pToken, channel, 'message_created');
    await wait(300);

    const replyRes = await authedFetch(
      sToken,
      `/cabinet/conversations/${conversationId}/messages`,
      {
        method: 'POST',
        body: JSON.stringify({ body: `e2e-d3-s-${Date.now().toString(36)}` }),
      },
    );
    expect(replyRes.status, 'POST /cabinet/conversations/:id/messages → 201').toBe(201);

    const latencyMs = await ws.promise;
    await ws.page.close();
    expect(latencyMs, 'WS event message_created attendu côté P').not.toBeNull();
    if (latencyMs !== null && latencyMs > 2000) console.warn(`[D3] WS P←S latence ${latencyMs}ms > 2s`);
  });

  test('Étape 5 : S marque lu → P reçoit event read (double coche)', async ({ context }) => {
    const channel = `conversation:${conversationId}`;
    const ws = await subscribeWs(context, pToken, channel, 'read');
    await wait(300);

    const readRes = await authedFetch(sToken, `/cabinet/conversations/${conversationId}/read`, {
      method: 'POST',
    });
    expect(
      [200, 204],
      `POST /cabinet/conversations/:id/read → 200/204 (obtenu ${readRes.status})`,
    ).toContain(readRes.status);

    const latencyMs = await ws.promise;
    await ws.page.close();
    expect(latencyMs, 'WS event read attendu côté P (double coche)').not.toBeNull();
    if (latencyMs !== null && latencyMs > 2000) console.warn(`[D3] WS P←S read ${latencyMs}ms > 2s`);
  });
});
