/**
 * ED4 — Ordonnance + profil public praticien (E2E flow)
 *
 * Parcours :
 *   1. Ordonnance : loginAs(practitioner)
 *                  → POST /v1/cabinet/prescriptions → ordonnance créée (201)
 *                  → POST /v1/cabinet/prescriptions/:id/sign → signée (stub Yousign)
 *   2. Profil public : PATCH /v1/cabinet/provider → profil mis à jour
 *                      PUT /v1/cabinet/provider/listing → listing activé
 *                      GET /v1/pro/verification → statut vérification lisible
 *                      POST /v1/pro/verification → RPPS soumis (202 pending)
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL        URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL    URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PATIENT_ID       UUID du patient seed (pour la prescription)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

const SEED_PATIENT_ID =
  process.env.SEED_PATIENT_ID ?? '00000000-0000-0000-0000-000000000002';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Créer une ordonnance puis la signer
// ─────────────────────────────────────────────────────────────────────────────
test('créer ordonnance (POST /v1/cabinet/prescriptions) → signer (POST …/:id/sign)', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Page nouvelle ordonnance : formulaire visible ─────────────────────
  await page.goto('/praticien/ordonnances/new');
  await expect(page.locator('form#form-new-prescription')).toBeVisible({ timeout: 15_000 });

  // ── 3. POST /v1/cabinet/prescriptions via UI → HTTP 201 ──────────────────
  await page.locator('input[name="patient_id"]').fill(SEED_PATIENT_ID);
  await page.locator('input[name="item_label"]').fill('Amoxicilline 500 mg');
  await page.locator('input[name="item_posology"]').fill('1 gélule 3×/jour');
  await page.locator('input[name="item_duration"]').fill('7 jours');
  await page.locator('input[name="item_quantity"]').fill('1');
  await page.locator('form#form-new-prescription button[type="submit"]').click();

  // Attendre le badge HTTP 201 dans #badge-new
  await expect(page.locator('#badge-new')).toContainText('HTTP 201', { timeout: 15_000 });

  // ── 4. Extraire l'id de l'ordonnance créée depuis le lien "Signer" ────────
  const signLink = page.locator('#badge-new a[href*="/sign"]');
  await expect(signLink).toBeVisible({ timeout: 10_000 });
  const signHref = await signLink.getAttribute('href');
  expect(signHref).toBeTruthy();
  // href = /praticien/ordonnances/{uuid}/sign
  const prescriptionId = (signHref ?? '').split('/praticien/ordonnances/')[1]?.replace('/sign', '') ?? '';
  expect(prescriptionId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );

  // ── 5. Vérifier via API directe que l'ordonnance existe ──────────────────
  const { getStatus } = await page.evaluate(
    async ({ apiBase, rxId }: { apiBase: string; rxId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(
        `${apiBase}/v1/cabinet/prescriptions/${encodeURIComponent(rxId)}`,
        { headers: { Authorization: `Bearer ${jwt}` } },
      );
      return { getStatus: resp.status };
    },
    { apiBase: API_BASE, rxId: prescriptionId },
  );
  expect(getStatus).toBe(200);

  // ── 6. Naviguer vers la page de signature ────────────────────────────────
  await page.goto(`/praticien/ordonnances/${prescriptionId}/sign`);
  await expect(page.locator('form#form-sign')).toBeVisible({ timeout: 15_000 });
  // L'auto-load du GET doit afficher l'ordonnance (result-get success)
  await expect(page.locator('#result-get')).toHaveClass(/success/, { timeout: 10_000 });

  // ── 7. POST /v1/cabinet/prescriptions/:id/sign via UI ────────────────────
  await page.locator('#btn-sign').click();
  // Attendre le badge de signature
  await expect(page.locator('#badge-sign')).toContainText(/HTTP 2/, { timeout: 20_000 });
  // Le résultat doit être success (2xx)
  await expect(page.locator('#result-sign')).toHaveClass(/success/, { timeout: 10_000 });
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Profil public — PATCH provider + PUT listing + GET/POST RPPS
// ─────────────────────────────────────────────────────────────────────────────
test('profil public : PATCH /v1/cabinet/provider + PUT listing + GET/POST /v1/pro/verification', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Page profil public : tous les formulaires visibles ────────────────
  await page.goto('/praticien/profil-public');
  await expect(page.locator('form#form-provider')).toBeVisible({ timeout: 15_000 });
  await expect(page.locator('form#form-listing')).toBeVisible();
  await expect(page.locator('form#form-verif-get')).toBeVisible();
  await expect(page.locator('form#form-verif-post')).toBeVisible();

  // ── 3. PATCH /v1/cabinet/provider via UI → 2xx ───────────────────────────
  await page.locator('input[name="specialty"]').fill('chirurgien-dentiste');
  await page.locator('textarea[name="bio"]').fill('Praticien spécialisé en implantologie.');
  await page.locator('form#form-provider button[type="submit"]').click();

  await expect(page.locator('#badge-provider')).toContainText(/HTTP 2/, { timeout: 15_000 });
  await expect(page.locator('#result-provider')).toHaveClass(/success/, { timeout: 10_000 });

  // ── 4. PUT /v1/cabinet/provider/listing via UI (activer) → 2xx ───────────
  await page.locator('input[name="is_listed"][value="true"]').check();
  await page.locator('form#form-listing button[type="submit"]').click();

  await expect(page.locator('#badge-listing')).toContainText(/HTTP 2/, { timeout: 15_000 });
  await expect(page.locator('#result-listing')).toHaveClass(/success/, { timeout: 10_000 });

  // ── 5. GET /v1/pro/verification via UI → réponse lisible ─────────────────
  await page.locator('form#form-verif-get button[type="submit"]').click();
  // Attendre un badge HTTP quelconque (200 ou 404 si pas encore soumis)
  await expect(page.locator('#badge-verif-get')).toContainText(/HTTP /, { timeout: 15_000 });

  // ── 6. POST /v1/pro/verification (RPPS stub) via API directe → 202 ───────
  const { postVerifStatus, postVerifData } = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/pro/verification`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ rpps: '12345678901' }),
      });
      const data = resp.ok
        ? ((await resp.json()) as { status?: string })
        : null;
      return { postVerifStatus: resp.status, postVerifData: data };
    },
    API_BASE,
  );

  expect(postVerifStatus).toBeLessThan(300);
  // Le stub retourne pending (202) ou already_verified (200)
  if (postVerifStatus === 202) {
    expect(postVerifData?.status).toBe('pending');
  }

  // ── 7. GET /v1/pro/verification via API directe → statut présent ─────────
  const { getVerifStatus, getVerifData } = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/pro/verification`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as { status?: string })
        : null;
      return { getVerifStatus: resp.status, getVerifData: data };
    },
    API_BASE,
  );

  expect(getVerifStatus).toBe(200);
  expect(getVerifData).not.toBeNull();
  expect(['pending', 'verified', 'rejected']).toContain(getVerifData?.status);
});
