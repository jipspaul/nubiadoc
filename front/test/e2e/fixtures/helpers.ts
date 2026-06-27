import { createHmac } from 'crypto';

import { request as playwrightRequest } from '@playwright/test';

export const API = process.env.API_BASE_URL ?? 'http://localhost:8080/v1';

/**
 * Authentifie via POST /v1/auth/login et retourne l'access_token JWT.
 * Lève une erreur si le login échoue (backend inaccessible ou credentials invalides).
 */
export async function loginApi(email: string, password: string): Promise<string> {
  const ctx = await playwrightRequest.newContext();
  try {
    const res = await ctx.post(`${API}/auth/login`, {
      data: { email, password },
    });
    if (!res.ok()) {
      throw new Error(`Login échoué pour ${email}: HTTP ${res.status()}`);
    }
    const body = await res.json();
    return body.access_token as string;
  } finally {
    await ctx.dispose();
  }
}

/**
 * Effectue un fetch authentifié vers l'API.
 * Délègue à l'API fetch native du runtime (Node 18+/Playwright).
 */
export function authedFetch(
  token: string,
  path: string,
  options?: RequestInit,
): Promise<Response> {
  return fetch(`${API}${path}`, {
    method: 'GET',
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(options?.headers as Record<string, string>),
    },
  });
}

const YOUSIGN_SECRET = process.env.YOUSIGN_WEBHOOK_SECRET ?? 'dev-yousign-secret';
const STRIPE_SECRET = process.env.STRIPE_WEBHOOK_SECRET ?? 'dev-stripe-secret';

/**
 * Simule un webhook prestataire avec signature HMAC valide (env dev).
 *
 * Yousign : HMAC-SHA256(secret, body) → X-Yousign-Signature-256: sha256=<hex>
 * Stripe  : HMAC-SHA256(secret, "<ts>.<body>") → Stripe-Signature: t=<ts>,v1=<hex>
 *
 * Idempotent par conception : rejouer le même event_id doit renvoyer 200 sans
 * effet de bord (le backend filtre les événements déjà traités).
 */
export function mockExternalWebhook(
  provider: 'yousign' | 'stripe',
  eventPayload: Record<string, unknown>,
): Promise<Response> {
  const body = JSON.stringify(eventPayload);

  if (provider === 'yousign') {
    const sig = createHmac('sha256', YOUSIGN_SECRET).update(body).digest('hex');
    return fetch(`${API}/webhooks/yousign`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Yousign-Signature-256': `sha256=${sig}`,
      },
      body,
    });
  }

  // Stripe : t=<unix_timestamp>,v1=<HMAC-SHA256(secret, "<ts>.<body>")>
  const ts = Math.floor(Date.now() / 1000).toString();
  const sig = createHmac('sha256', STRIPE_SECRET).update(`${ts}.${body}`).digest('hex');
  return fetch(`${API}/webhooks/stripe`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Stripe-Signature': `t=${ts},v1=${sig}`,
    },
    body,
  });

/**
 * Crée un RDV (P) puis le confirme (S). Retourne l'appointment_id.
 * Extrait du scénario A1 pour être réutilisé par A4 et autres.
 */
export async function bookAndConfirmAppointment(
  pToken: string,
  sToken: string,
  providerId: string,
  slotId: string,
): Promise<string> {
  const bookRes = await authedFetch(pToken, '/appointments', {
    method: 'POST',
    body: JSON.stringify({ provider_id: providerId, slot_id: slotId, motif: 'e2e-a4-waiting-room' }),
  });
  if (!bookRes.ok) throw new Error(`POST /appointments échoué: HTTP ${bookRes.status}`);
  const { appointment_id } = (await bookRes.json()) as { appointment_id: string };

  const confirmRes = await authedFetch(sToken, `/cabinet/appointments/${appointment_id}/confirm`, {
    method: 'POST',
  });
  if (!confirmRes.ok)
    throw new Error(`POST /cabinet/appointments/:id/confirm échoué: HTTP ${confirmRes.status}`);

  return appointment_id;
}
