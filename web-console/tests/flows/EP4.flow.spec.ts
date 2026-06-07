/**
 * EP4 — Messagerie patient (E2E flow)
 *
 * Parcours : loginAs(patient) → créer conversation (POST /v1/conversations)
 *            → envoyer message → marquer comme lu (auto) → relire la conversation
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 * SEED_CABINET_ID doit correspondre à un cabinet présent dans le jeu de seed.
 *
 * Variables d'environnement :
 *   SEED_CABINET_ID      UUID du cabinet seed (requis pour create-conv)
 *   FLOWS_API_BASE_URL   URL de l'API backend (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const SEED_CABINET_ID =
  process.env.SEED_CABINET_ID ?? '00000000-0000-0000-0000-000000000001';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

test('créer conversation → envoyer message → marquer lu → relire', async ({ page }) => {
  // ── 1. Connexion ────────────────────────────────────────────────────────────
  await loginAs(page, 'patient');

  // ── 2. Liste des conversations ──────────────────────────────────────────────
  await page.goto('/patient/messages');
  await expect(page.locator('#conv-loading')).toBeHidden({ timeout: 10_000 });

  // ── 3. Ouvrir le formulaire "Nouvelle conversation" ─────────────────────────
  await page.locator('#btn-new-conv').click();
  await expect(page.locator('#dialog-new-conv')).toBeVisible();

  // ── 4. POST /v1/conversations via UI → 201 (idempotent si déjà existante) ───
  await page.locator('input[name="cabinet_id"]').fill(SEED_CABINET_ID);
  await page.locator('#form-new-conv button[type="submit"]').click();

  // ── 5. Redirection vers /patient/messages/{uuid} ────────────────────────────
  await page.waitForURL(/\/patient\/messages\/[0-9a-f-]+$/, { timeout: 15_000 });
  const convId = page.url().split('/patient/messages/')[1];
  expect(convId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );

  // ── 6. Thread chargé → markRead déclenché automatiquement ───────────────────
  await expect(page.locator('#msg-loading')).toBeHidden({ timeout: 10_000 });
  await expect(page.locator('#reply-form')).toBeVisible();

  // ── 7. Envoyer un message ───────────────────────────────────────────────────
  const msgBody = `Test EP4 — ${Date.now()}`;
  await page.locator('#reply-body').fill(msgBody);
  await page.locator('#reply-submit').click();

  // ── 8. Message visible dans le thread (GET /v1/conversations/{id}/messages) ─
  await expect(page.locator('#msg-list')).toBeVisible({ timeout: 10_000 });
  await expect(page.locator('#msg-list')).toContainText(
    msgBody.slice(0, 12),
    { timeout: 10_000 },
  );

  // ── 9. API : GET /v1/conversations → unread_count = 0 confirme markRead ─────
  const { listStatus, unreadCount } = await page.evaluate(
    async ({ apiBase, convId }: { apiBase: string; convId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/conversations`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      let list: Array<{ id: string; unread_count?: number }> = [];
      if (resp.ok) {
        list = (await resp.json()) as typeof list;
      }
      const conv = list.find((c) => c.id === convId);
      return { listStatus: resp.status, unreadCount: conv?.unread_count ?? -1 };
    },
    { apiBase: API_BASE, convId },
  );
  expect(listStatus).toBeLessThan(300);
  expect(unreadCount).toBe(0);

  // ── 10. Retour à la liste : conversation présente, unread_count = 0 (UI) ────
  await page.goto('/patient/messages');
  await expect(page.locator('#conv-loading')).toBeHidden({ timeout: 10_000 });
  const convItem = page.locator(`[data-conversation-id="${convId}"]`);
  await expect(convItem).toBeVisible({ timeout: 5_000 });
  // badge data-zero indique unread_count = 0 (markRead ✓)
  await expect(convItem.locator('.conv-badge[data-zero]')).toBeVisible();
});

test('scope clinical non visible pour le patient standard (cloisonnement)', async ({ page }) => {
  await loginAs(page, 'patient');

  // Appel direct API depuis le contexte navigateur : le JWT est en localStorage
  const { status, conversations } = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/conversations`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return {
        status: resp.status,
        conversations: resp.ok
          ? ((await resp.json()) as Array<{ id: string; scope?: string }>)
          : ([] as Array<{ id: string; scope?: string }>),
      };
    },
    API_BASE,
  );

  expect(status).toBeLessThan(300);
  const clinical = (
    conversations as Array<{ scope?: string }>
  ).filter((c) => c.scope === 'clinical');
  // Le patient standard ne doit voir aucune conversation à portée clinical
  expect(clinical).toHaveLength(0);
});
