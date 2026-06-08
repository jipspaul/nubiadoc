/**
 * EP2 — Recherche → réservation patient (E2E flow)
 *
 * Parcours : loginAs(patient) → annuaire (/search) → résultats praticiens
 *            → profil praticien → choisir créneau → POST /v1/appointments
 *            → RDV visible dans Mes RDV (/patient/rdv) avec statut `pending`
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P5
 *             (agenda praticien avec créneaux disponibles).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL       URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL   URL de l'API backend (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

test('search → profil praticien → créneau → POST appointment → RDV visible dans Mes RDV', async ({ page }) => {
  // ── 1. Connexion ─────────────────────────────────────────────────────────
  await loginAs(page, 'patient');

  // ── 2. Annuaire : page de recherche ──────────────────────────────────────
  await page.goto('/search');
  await expect(page.locator('#search-form')).toBeVisible();

  // ── 3. Soumettre une recherche ────────────────────────────────────────────
  await page.locator('#search-input').fill('dentiste');
  await page.locator('#search-form button[type="submit"]').click();

  // ── 4. Page de résultats (/search/providers?q=dentiste) ───────────────────
  await page.waitForURL(/\/search\/providers/, { timeout: 10_000 });
  // Attendre que la liste des praticiens soit chargée (plus de "Chargement…")
  await expect(page.locator('#providers-list .loading')).toBeHidden({
    timeout: 15_000,
  });

  // Au moins une carte praticien doit être présente
  const firstCard = page.locator('#providers-list .provider-card').first();
  await expect(firstCard).toBeVisible({ timeout: 10_000 });

  // ── 5.a. GET /v1/search/providers?q=dentiste → 200 ──────────────────────
  const searchApiStatus = await page.evaluate(
    async ({ apiBase }: { apiBase: string }) => {
      const resp = await fetch(
        `${apiBase}/v1/search/providers?q=${encodeURIComponent('dentiste')}`,
      );
      return resp.status;
    },
    { apiBase: API_BASE },
  );
  expect(searchApiStatus).toBe(200);

  // ── 5. Naviguer vers le profil du premier praticien ───────────────────────
  const profileLink = firstCard.locator('a.btn-secondary');

  // Récupérer l'id praticien depuis le href avant de cliquer
  const profileHref = await profileLink.getAttribute('href');
  expect(profileHref).toBeTruthy();
  const profileProviderId = (profileHref as string).split('/').pop() ?? '';
  expect(profileProviderId).not.toBe('');

  // GET /v1/providers/:id → 200 ──────────────────────────────────────────────
  const providerApiStatus = await page.evaluate(
    async ({ apiBase, pid }: { apiBase: string; pid: string }) => {
      const resp = await fetch(`${apiBase}/v1/providers/${pid}`);
      return resp.status;
    },
    { apiBase: API_BASE, pid: profileProviderId },
  );
  expect(providerApiStatus).toBe(200);

  await profileLink.click();

  // ── 6. Page profil praticien (/search/providers/{id}) ────────────────────
  await page.waitForURL(/\/search\/providers\/[^/]+$/, { timeout: 10_000 });
  await expect(page.locator('#provider-name')).not.toHaveText('Chargement…', {
    timeout: 10_000,
  });
  await expect(page.locator('#provider-article')).toBeVisible();

  // ── 7. Attendre que les créneaux soient chargés ───────────────────────────
  await expect(page.locator('#slots-list .muted')).toBeHidden({
    timeout: 15_000,
  });
  const firstSlotLink = page.locator('#slots-list .slot-item a').first();
  await expect(firstSlotLink).toBeVisible({ timeout: 10_000 });

  // Extraire slot_id et provider_id depuis le href du lien créneau
  const slotHref = await firstSlotLink.getAttribute('href');
  expect(slotHref).toBeTruthy();
  expect(slotHref).toContain('slot_id=');
  expect(slotHref).toContain('provider_id=');

  const slotUrl = new URL(slotHref as string, 'http://x');
  const slotId = slotUrl.searchParams.get('slot_id') ?? '';
  const providerId = slotUrl.searchParams.get('provider_id') ?? '';
  expect(slotId).not.toBe('');
  expect(providerId).not.toBe('');

  // ── 7.a GET /v1/search/slots?provider_id=… → 200 ─────────────────────────
  const slotsApiStatus = await page.evaluate(
    async ({ apiBase, pid }: { apiBase: string; pid: string }) => {
      const url = `${apiBase}/v1/search/slots?${new URLSearchParams({ provider_id: pid }).toString()}`;
      const resp = await fetch(url);
      return resp.status;
    },
    { apiBase: API_BASE, pid: providerId },
  );
  expect(slotsApiStatus).toBe(200);

  // ── 8. POST /v1/appointments → 201 avec un id ─────────────────────────────
  const { postStatus, appointmentId } = await page.evaluate(
    async ({
      apiBase,
      slotId,
      providerId,
    }: {
      apiBase: string;
      slotId: string;
      providerId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const idempotencyKey = crypto.randomUUID();
      const resp = await fetch(`${apiBase}/v1/appointments`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
        body: JSON.stringify({ slot_id: slotId, provider_id: providerId }),
      });
      const text = await resp.text();
      let data: Record<string, unknown> = {};
      try {
        data = JSON.parse(text) as Record<string, unknown>;
      } catch {
        data = {};
      }
      return {
        postStatus: resp.status,
        appointmentId: (data['id'] ?? data['appointment_id'] ?? '') as string,
      };
    },
    { apiBase: API_BASE, slotId, providerId },
  );

  expect(postStatus).toBe(201);
  expect(appointmentId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );

  // ── 9. GET /v1/appointments → la liste contient le RDV créé ───────────────
  const { listStatus, found } = await page.evaluate(
    async ({
      apiBase,
      appointmentId,
    }: {
      apiBase: string;
      appointmentId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/appointments`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      let list: Array<{ id: string; status?: string }> = [];
      if (resp.ok) {
        list = (await resp.json()) as Array<{ id: string; status?: string }>;
      }
      const found = list.find((a) => a.id === appointmentId);
      return { listStatus: resp.status, found };
    },
    { apiBase: API_BASE, appointmentId },
  );

  expect(listStatus).toBeLessThan(300);
  expect(found).toBeDefined();
  expect(found?.status).toBe('pending');

  // ── 10. Page /patient/rdv : le RDV apparaît dans l'UI avec statut pending ─
  await page.goto('/patient/rdv');
  await expect(page.locator('#upcoming-loading')).toBeHidden({
    timeout: 15_000,
  });

  const rdvItem = page.locator(`a[href="/patient/rdv/${appointmentId}"]`);
  await expect(rdvItem).toBeVisible({ timeout: 10_000 });
  await expect(rdvItem.locator('.rdv-badge[data-status="pending"]')).toBeVisible();

  // ── 11. Reset — annuler le RDV créé ──────────────────────────────────────
  await page.evaluate(
    async ({
      apiBase,
      appointmentId,
    }: {
      apiBase: string;
      appointmentId: string;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      await fetch(`${apiBase}/v1/appointments/${appointmentId}/cancel`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${jwt}` },
      });
    },
    { apiBase: API_BASE, appointmentId },
  );
});

test('résultats de recherche : au moins un praticien listé sur /search/providers', async ({ page }) => {
  await loginAs(page, 'patient');

  await page.goto('/search/providers');
  await expect(page.locator('#providers-section')).toBeVisible();

  // Attendre la fin du chargement
  await expect(page.locator('#providers-list .loading')).toBeHidden({
    timeout: 15_000,
  });

  // Au moins un praticien doit être listé (seed P5 peuple l'agenda)
  const cards = page.locator('#providers-list .provider-card');
  await expect(cards.first()).toBeVisible({ timeout: 10_000 });
  expect(await cards.count()).toBeGreaterThanOrEqual(1);
});
