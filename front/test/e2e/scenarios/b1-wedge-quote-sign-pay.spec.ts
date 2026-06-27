/**
 * B1 — Devis → signature Yousign → paiement Stripe (E2E backend mocké)
 *
 * Tous les appels prestataires sont stubés via mockExternalWebhook :
 * - La redirect_url Yousign est inspectée mais jamais suivie (zéro appel yousign.com).
 * - Les webhooks sont injectés directement avec signature HMAC valide (env dev).
 *
 * Done-when :
 * - Scénario PASS du bout en bout.
 * - Idempotence : webhook rejoué 2× → un seul changement d'état (pas de double-paiement).
 *
 * Refs : front/docs/e2e-scenarios.md §B1
 *        docs/12-api-reference.md §10 (wedge) + §21 (webhooks)
 */

import { test, expect } from '@playwright/test';
import { loginApi, authedFetch, mockExternalWebhook } from '../fixtures/helpers';

const D_EMAIL = process.env.CRED_PRACTICIEN_EMAIL ?? 'praticien@nubia-demo.fr';
const D_PASS = process.env.CRED_PRACTICIEN_PASSWORD ?? 'demo-pass';
const P_EMAIL = process.env.CRED_PATIENT_EMAIL ?? 'patient1@nubia-demo.fr';
const P_PASS = process.env.CRED_PATIENT_PASSWORD ?? 'demo-pass';
const DEMO_PATIENT_ID = process.env.DEMO_PATIENT_ID ?? 'demo-patient-001';

test.describe('B1 — Devis → signature Yousign → paiement Stripe', () => {
  test.describe.configure({ mode: 'serial' });

  let dToken: string;
  let pToken: string;
  let quoteId: string;
  let paymentId: string;
  let sigEventId: string;
  let payEventId: string;

  test.beforeAll(async () => {
    [dToken, pToken] = await Promise.all([
      loginApi(D_EMAIL, D_PASS),
      loginApi(P_EMAIL, P_PASS),
    ]);
  });

  // ── Step 1 : D crée le devis ─────────────────────────────────────────────

  test('D crée un devis items + deposit_pct=30 (POST /cabinet/quotes → 201)', async () => {
    const res = await authedFetch(dToken, '/cabinet/quotes', {
      method: 'POST',
      body: JSON.stringify({
        patient_id: DEMO_PATIENT_ID,
        items: [
          {
            label: 'Détartrage',
            qty: 1,
            unit_amount_cents: 8000,
            amo_part_cents: 3000,
            amc_part_cents: 2000,
          },
          {
            label: 'Composite antérieur',
            qty: 2,
            unit_amount_cents: 15000,
          },
        ],
        deposit_pct: 30,
      }),
    });
    expect(res.status, `POST /cabinet/quotes attendu 201, reçu ${res.status}`).toBe(201);
    const body = (await res.json()) as { quote_id: string };
    expect(body.quote_id, 'quote_id absent de la réponse').toBeTruthy();
    quoteId = body.quote_id;
    sigEventId = `e2e-b1-sig-${quoteId}`;
    payEventId = `e2e-b1-pay-${quoteId}`;
  });

  // ── Step 2 : P voit le devis en attente ──────────────────────────────────

  test('P voit le devis "en attente signature" dans GET /quotes', async () => {
    const res = await authedFetch(pToken, '/quotes');
    expect(res.status).toBe(200);
    const body = (await res.json()) as unknown;
    const quotes = (
      Array.isArray(body) ? body : (body as { data: unknown[] }).data ?? []
    ) as Array<{ quote_id: string; status: string }>;
    const quote = quotes.find((q) => q.quote_id === quoteId);
    expect(quote, `Devis ${quoteId} absent de GET /quotes du patient`).toBeTruthy();
    expect(quote!.status, `status attendu pending*, obtenu ${quote!.status}`).toMatch(/^pending/);
  });

  // ── Step 3 : P initie la signature (aucun appel réel yousign.com) ─────────

  test('P initie signature — redirect_url pointe Yousign, jamais suivie', async () => {
    const res = await authedFetch(pToken, `/quotes/${quoteId}/signature`, {
      method: 'POST',
    });
    expect(res.status, `POST /quotes/${quoteId}/signature attendu 202, reçu ${res.status}`).toBe(
      202,
    );
    const body = (await res.json()) as { provider: string; redirect_url?: string };
    expect(body.provider, 'provider attendu "yousign"').toBe('yousign');
    // Vérifie que le backend a généré une URL Yousign SANS la suivre depuis le harnais.
    // L'absence d'appel réseau vers yousign.com est garantie : on ne fetch jamais redirect_url.
    expect(body.redirect_url ?? '', 'redirect_url doit pointer vers Yousign').toMatch(/yousign/i);
  });

  // ── Step 4 : Webhook Yousign signature.completed → quote signed ───────────

  test('Webhook Yousign → quote status=signed, signed_at défini', async () => {
    const wRes = await mockExternalWebhook('yousign', {
      event_id: sigEventId,
      event_kind: 'signature.completed',
      signature_request: { id: sigEventId, status: 'done', external_id: quoteId },
    });
    expect(wRes.status, `POST /webhooks/yousign attendu 200, reçu ${wRes.status}`).toBe(200);

    const qRes = await authedFetch(pToken, `/quotes/${quoteId}`);
    expect(qRes.status).toBe(200);
    const q = (await qRes.json()) as { status: string; signed_at: string };
    expect(q.status, `status attendu "signed", obtenu "${q.status}"`).toBe('signed');
    expect(q.signed_at, 'signed_at doit être défini après signature').toBeTruthy();
  });

  // ── Idempotence Yousign ───────────────────────────────────────────────────

  test('Idempotence Yousign : webhook rejoué 2× → status toujours "signed"', async () => {
    await mockExternalWebhook('yousign', {
      event_id: sigEventId,
      event_kind: 'signature.completed',
      signature_request: { id: sigEventId, status: 'done', external_id: quoteId },
    });
    const qRes = await authedFetch(pToken, `/quotes/${quoteId}`);
    const q = (await qRes.json()) as { status: string };
    expect(
      q.status,
      'Idempotence Yousign : status doit rester "signed" après replay',
    ).toBe('signed');
  });

  // ── Step 5 : P paie l'acompte (Stripe PaymentIntent) ─────────────────────

  test("P crée PaymentIntent acompte (POST /payments/intent → 201)", async () => {
    const res = await authedFetch(pToken, '/payments/intent', {
      method: 'POST',
      body: JSON.stringify({ quote_id: quoteId, kind: 'deposit', method: 'card' }),
      headers: { 'Idempotency-Key': payEventId },
    });
    expect(res.status, `POST /payments/intent attendu 201, reçu ${res.status}`).toBe(201);
    const body = (await res.json()) as { payment_id: string; client_secret: string };
    expect(body.payment_id, 'payment_id absent').toBeTruthy();
    expect(body.client_secret, 'client_secret Stripe absent').toBeTruthy();
    paymentId = body.payment_id;
  });

  // ── Step 6 : Webhook Stripe payment_intent.succeeded → paid ──────────────

  test('Webhook Stripe → payment status=paid (POST /webhooks/stripe → 200)', async () => {
    const wRes = await mockExternalWebhook('stripe', {
      id: payEventId,
      type: 'payment_intent.succeeded',
      data: {
        object: {
          id: paymentId,
          status: 'succeeded',
          metadata: { nubia_payment_id: paymentId },
        },
      },
    });
    expect(wRes.status, `POST /webhooks/stripe attendu 200, reçu ${wRes.status}`).toBe(200);
  });

  // ── Idempotence Stripe ────────────────────────────────────────────────────

  test('Idempotence Stripe : webhook rejoué 2× → exactement 1 paiement', async () => {
    await mockExternalWebhook('stripe', {
      id: payEventId,
      type: 'payment_intent.succeeded',
      data: {
        object: {
          id: paymentId,
          status: 'succeeded',
          metadata: { nubia_payment_id: paymentId },
        },
      },
    });
    const pRes = await authedFetch(pToken, '/payments');
    expect(pRes.status).toBe(200);
    const body = (await pRes.json()) as unknown;
    const payments = (
      Array.isArray(body) ? body : (body as { data: unknown[] }).data ?? []
    ) as Array<{ payment_id: string; quote_id: string; status: string }>;
    const forQuote = payments.filter((p) => p.quote_id === quoteId);
    expect(
      forQuote.length,
      `Idempotence Stripe : attendu 1 paiement pour le devis, trouvé ${forQuote.length}`,
    ).toBe(1);
    expect(forQuote[0].status, 'payment status attendu "paid"').toBe('paid');
  });

  // ── Step 7 : D voit "Signé + Payé" avec date et SHA signature ────────────

  test('D voit le devis signé+payé avec signed_at et SHA256 signature', async () => {
    const res = await authedFetch(dToken, `/cabinet/quotes/${quoteId}`);
    expect(res.status).toBe(200);
    const q = (await res.json()) as Record<string, unknown>;
    expect(q.status, `status attendu "signed", obtenu "${q.status}"`).toBe('signed');
    expect(q.signed_at, 'signed_at doit être défini').toBeTruthy();
    expect(q.signature_sha256 ?? q.sha256, 'SHA256 signature doit être présent').toBeTruthy();
    const payStatus = String(q.payment_status ?? q.deposit_status ?? '');
    expect(
      ['paid', 'partial', 'deposit_paid'].some((s) => payStatus === s || payStatus.includes(s)),
      `payment_status attendu paid/deposit_paid, obtenu "${payStatus}"`,
    ).toBe(true);
  });
});
