import { createHmac } from 'crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

import { request as playwrightRequest } from '@playwright/test';

// Cache disque : Playwright REDÉMARRE le process worker après chaque échec de
// test — un cache purement en mémoire serait perdu et chaque redémarrage
// re-frapperait /auth/login (rate-limité). TTL court, JWT valides bien plus
// longtemps que la durée d'un run.
const CACHE_DIR = join(__dirname, '..', '.e2e-cache');
const CACHE_TTL_MS = 20 * 60 * 1000;

export function diskCacheRead(name: string): Record<string, unknown> {
  try {
    const f = join(CACHE_DIR, name);
    if (!existsSync(f)) return {};
    const { at, data } = JSON.parse(readFileSync(f, 'utf8'));
    return Date.now() - at < CACHE_TTL_MS ? data : {};
  } catch {
    return {};
  }
}

export function diskCacheWrite(name: string, data: Record<string, unknown>): void {
  try {
    mkdirSync(CACHE_DIR, { recursive: true });
    writeFileSync(join(CACHE_DIR, name), JSON.stringify({ at: Date.now(), data }));
  } catch {
    // best-effort
  }
}

export const API = process.env.API_BASE_URL ?? 'http://localhost:8080/v1';

// Cache par email (process worker) : évite de re-frapper /auth/login — le
// backend rate-limite les tentatives (429) quand plusieurs specs se loguent
// avec les mêmes comptes seed.
const tokenCache = new Map<string, string>(
  Object.entries(diskCacheRead('tokens.json') as Record<string, string>),
);

// Le backend plafonne /auth/login à 5 tentatives/minute PAR IP
// (api/src/auth/login.rs IP_RATE_MAX_ATTEMPTS). Toute tentative de login —
// API ou formulaire navigateur — doit passer par ce sas : 13s d'écart
// garantissent de rester sous le plafond quel que soit l'ordre des specs.
const LOGIN_SPACING_MS = 13_000;
let lastLoginSlot = Promise.resolve();
let lastLoginAt = 0;

export function loginThrottle(): Promise<void> {
  const slot = lastLoginSlot.then(async () => {
    const wait = lastLoginAt + LOGIN_SPACING_MS - Date.now();
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    lastLoginAt = Date.now();
  });
  lastLoginSlot = slot;
  return slot;
}

/**
 * Authentifie via POST /v1/auth/login et retourne l'access_token JWT.
 * Mémoïsé par email, avec backoff sur 429 (rate-limit login).
 * Lève une erreur si le login échoue (backend inaccessible ou credentials invalides).
 */
export async function loginApi(email: string, password: string): Promise<string> {
  const cached = tokenCache.get(email);
  if (cached) return cached;

  const ctx = await playwrightRequest.newContext();
  try {
    for (let attempt = 1; ; attempt++) {
      await loginThrottle();
      const res = await ctx.post(`${API}/auth/login`, {
        data: { email, password },
      });
      if (res.status() === 429 && attempt < 4) {
        await new Promise((r) => setTimeout(r, attempt * 15_000));
        continue;
      }
      if (!res.ok()) {
        throw new Error(`Login échoué pour ${email}: HTTP ${res.status()}`);
      }
      const body = await res.json();
      const token = body.access_token as string;
      tokenCache.set(email, token);
      diskCacheWrite('tokens.json', Object.fromEntries(tokenCache));
      return token;
    }
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
}
