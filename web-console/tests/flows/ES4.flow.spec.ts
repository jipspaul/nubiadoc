/**
 * ES4 — Parcours secrétaire Cloisonnement (E2E flow)
 *
 * Valide le cloisonnement secret médical (R.4127-72) : secretary ≠ practitioner.
 *
 * Scénarios :
 *   1. login secrétaire → accès route praticien-only → 403 ou redirect /auth/login
 *   2. messagerie cabinet (GET /v1/cabinet/conversations) → aucune conversation
 *      scope=clinical visible pour la secrétaire
 *   3. middleware W5 : réponse HTTP non-200 (3xx ou 403) sur préfixe interdit
 *      (sans suivi de redirect)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *             R1 restauré (login pro porte cabinet_id+role dans le JWT).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL    URL de l'API backend (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Login secrétaire → route praticien-only → redirect hors /praticien/
// ─────────────────────────────────────────────────────────────────────────────
test('secrétaire bloquée sur route praticien-only : redirect hors /praticien/', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Accès à une route praticien-only ──────────────────────────────────
  await page.goto('/praticien/dashboard');

  // ── 3. Le middleware W5 redirige hors du préfixe /praticien/ ─────────────
  // (vers /auth/login?next=... ou /403 selon l'implémentation)
  const finalUrl = page.url();
  expect(finalUrl).not.toContain('/praticien/');
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Messagerie cabinet — aucune conversation scope=clinical
// ─────────────────────────────────────────────────────────────────────────────
test('messagerie cabinet : GET /v1/cabinet/conversations → aucune conversation scope=clinical', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. GET /v1/cabinet/conversations → filtrer scope=clinical ────────────
  const { status, clinicalCount } = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/conversations`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const conversations = resp.ok
        ? ((await resp.json()) as Array<{ id: string; scope?: string }>)
        : ([] as Array<{ id: string; scope?: string }>);
      const clinical = conversations.filter((c) => c.scope === 'clinical');
      return { status: resp.status, clinicalCount: clinical.length };
    },
    API_BASE,
  );

  // ── 3. L'API répond (2xx) et ne renvoie aucun message clinique ───────────
  expect(status).toBeLessThan(300);
  // Cloisonnement R.4127-72 : la secrétaire ne voit aucune conversation
  // à portée clinical (secret médical réservé aux praticiens)
  expect(clinicalCount).toBe(0);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 3 : Middleware W5 — réponse HTTP de blocage sur préfixe interdit
// ─────────────────────────────────────────────────────────────────────────────
test('middleware W5 : HTTP 3xx ou 403 sur préfixe praticien-only (sans suivi de redirect)', async ({ page }) => {
  // ── 1. Connexion secrétaire ───────────────────────────────────────────────
  await loginAs(page, 'secretary');

  // ── 2. Requête directe sans suivi de redirect (maxRedirects: 0) ──────────
  //    Le middleware doit répondre 3xx (redirect) ou 403 — jamais 200.
  const response = await page.request.get('/praticien/dashboard', {
    maxRedirects: 0,
  });

  // ── 3. Status doit être un redirect (3xx) ou 403 ─────────────────────────
  const status = response.status();
  const isBlocked = (status >= 300 && status < 400) || status === 403;
  expect(isBlocked, `Attendu 3xx ou 403, reçu ${status}`).toBe(true);

  // ── 4. Vérification sur une deuxième route praticien-only (agenda) ────────
  const responseAgenda = await page.request.get('/praticien/agenda', {
    maxRedirects: 0,
  });
  const statusAgenda = responseAgenda.status();
  const isBlockedAgenda =
    (statusAgenda >= 300 && statusAgenda < 400) || statusAgenda === 403;
  expect(isBlockedAgenda, `Attendu 3xx ou 403 sur /praticien/agenda, reçu ${statusAgenda}`).toBe(true);
});
