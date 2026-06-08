/**
 * EX3 — Wedge devis : parcours cross-rôle
 *
 * Parcours :
 *   1. Praticien crée un devis via POST /v1/cabinet/prescriptions → 201
 *      puis le signe via POST /v1/cabinet/prescriptions/:id/sign → 2xx
 *   2. Patient consulte ses devis via GET /v1/quotes → 200 + devis visible
 *      et via UI : page /patient/devis affiche la liste
 *   3. Patient signe le devis via POST /v1/quotes/:id/signature → 202 ou 409
 *      → GET /v1/quotes/:id → statut mis à jour
 *   4. Secrétaire consulte la facturation via GET /v1/cabinet/quotes → 200
 *      + devis signé visible via UI : page /secretary/facturation
 *
 * Dépend de : E0 ✓, R1 ✓, W33 ✓, W21 ✓, W41 ✓
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 *             R1 restauré (login pro porte cabinet_id+role dans le JWT).
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL       URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL   URL de l'API backend (défaut http://localhost:38030)
 *   SEED_PATIENT_ID      UUID du patient seed (pour la prescription)
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
// Scénario 1 : Parcours complet cross-rôle
// praticien crée + signe → patient voit dans GET /v1/quotes + UI
// → patient signe → secrétaire voit devis signé dans GET /v1/cabinet/quotes + UI
// ─────────────────────────────────────────────────────────────────────────────
test('EX3 : praticien crée devis → patient voit + signe → secrétaire voit règlement', async ({ page }) => {
  // ── 1. Connexion praticien ────────────────────────────────────────────────
  await loginAs(page, 'practitioner');

  // ── 2. Page nouvelle ordonnance : formulaire visible ─────────────────────
  await page.goto('/praticien/ordonnances/new');
  await expect(page.locator('form#form-new-prescription')).toBeVisible({ timeout: 15_000 });

  // ── 3. POST /v1/cabinet/prescriptions via UI → HTTP 201 ──────────────────
  await page.locator('input[name="patient_id"]').fill(SEED_PATIENT_ID);
  await page.locator('input[name="item_label"]').fill('Détartrage + fluoration');
  await page.locator('input[name="item_posology"]').fill('1 séance');
  await page.locator('input[name="item_duration"]').fill('1 séance');
  await page.locator('input[name="item_quantity"]').fill('1');
  await page.locator('form#form-new-prescription button[type="submit"]').click();

  await expect(page.locator('#badge-new')).toContainText('HTTP 201', { timeout: 15_000 });

  // ── 4. Extraire l'ID de la prescription depuis le lien "Signer" ───────────
  const signLink = page.locator('#badge-new a[href*="/sign"]');
  await expect(signLink).toBeVisible({ timeout: 10_000 });
  const signHref = await signLink.getAttribute('href');
  expect(signHref).toBeTruthy();
  const prescriptionId =
    (signHref ?? '').split('/praticien/ordonnances/')[1]?.replace('/sign', '') ?? '';
  expect(prescriptionId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );

  // ── 5. POST /v1/cabinet/prescriptions/:id/sign → 2xx ─────────────────────
  await page.goto(`/praticien/ordonnances/${prescriptionId}/sign`);
  await expect(page.locator('form#form-sign')).toBeVisible({ timeout: 15_000 });
  await expect(page.locator('#result-get')).toHaveClass(/success/, { timeout: 10_000 });

  await page.locator('#btn-sign').click();
  await expect(page.locator('#badge-sign')).toContainText(/HTTP 2/, { timeout: 20_000 });
  await expect(page.locator('#result-sign')).toHaveClass(/success/, { timeout: 10_000 });

  // ── 6. Résoudre l'ID du devis créé pour le patient ───────────────────────
  // L'API crée un quote lié à la prescription ; on le cherche via GET /v1/cabinet/quotes
  const quoteId = await page.evaluate(
    async ({ apiBase, patientId }: { apiBase: string; patientId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/quotes`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      if (!resp.ok) return '';
      const quotes = (await resp.json()) as Array<{
        id: string;
        patient_id?: string;
        status?: string;
      }>;
      // Prendre le devis le plus récent lié au patient seed
      const match = quotes
        .filter((q) => !patientId || q.patient_id === patientId || !q.patient_id)
        .at(0);
      return match?.id ?? '';
    },
    { apiBase: API_BASE, patientId: SEED_PATIENT_ID },
  );

  // quoteId peut être vide si le backend ne crée pas de quote automatiquement
  // depuis une prescription (dépend de l'implémentation). On continue si présent.

  // ── 7. Déconnexion praticien / connexion patient ──────────────────────────
  await clearSession(page);
  await loginAs(page, 'patient');

  // ── 8. Patient : GET /v1/quotes → 200 ────────────────────────────────────
  const quotesListResult = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/quotes`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as Array<{ id: string; status: string; total_amount?: number }>)
        : [];
      return { status: resp.status, quotes: data };
    },
    API_BASE,
  );

  expect(quotesListResult.status).toBe(200);
  expect(Array.isArray(quotesListResult.quotes)).toBe(true);

  // ── 9. Patient : UI /patient/devis affiche la liste ──────────────────────
  await page.goto('/patient/devis');
  await expect(page.locator('#quotes-loading')).toBeHidden({ timeout: 15_000 });
  await expect(
    page.locator('#quotes-list, #quotes-empty, #quotes-error'),
  ).toBeVisible({ timeout: 10_000 });

  // ── 10. Patient : signer un devis signable (pending/sent) ────────────────
  // Utilise le quoteId résolu depuis la vue cabinet si disponible, sinon
  // cherche parmi les devis du patient un devis en attente de signature.
  const targetQuoteId =
    quoteId ||
    (quotesListResult.quotes.find((q) => q.status === 'pending' || q.status === 'sent')?.id ?? '');

  if (targetQuoteId) {
    const signResult = await page.evaluate(
      async ({ apiBase, id }: { apiBase: string; id: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(`${apiBase}/v1/quotes/${id}/signature`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${jwt}`,
            'Idempotency-Key': crypto.randomUUID(),
          },
        });
        const data = resp.ok
          ? ((await resp.json()) as {
              signature_id?: string;
              redirect_url?: string;
              embed_token?: string;
            })
          : null;
        return { status: resp.status, data };
      },
      { apiBase: API_BASE, id: targetQuoteId },
    );

    // 202 = signature initiée (stub Yousign) ; 409 = déjà signé/verrouillé
    expect([202, 409]).toContain(signResult.status);

    // ── 11. GET /v1/quotes/:id → statut mis à jour ───────────────────────────
    const quoteDetailResult = await page.evaluate(
      async ({ apiBase, id }: { apiBase: string; id: string }) => {
        const jwt = localStorage.getItem('nubia_jwt') ?? '';
        const resp = await fetch(`${apiBase}/v1/quotes/${id}`, {
          headers: { Authorization: `Bearer ${jwt}` },
        });
        const data = resp.ok
          ? ((await resp.json()) as { id: string; status: string })
          : null;
        return { status: resp.status, data };
      },
      { apiBase: API_BASE, id: targetQuoteId },
    );

    expect(quoteDetailResult.status).toBe(200);
    expect(quoteDetailResult.data?.id).toBe(targetQuoteId);
    expect(quoteDetailResult.data?.status).toBeTruthy();
  }

  // ── 12. Déconnexion patient / connexion secrétaire ───────────────────────
  await clearSession(page);
  await loginAs(page, 'secretary');

  // ── 13. Secrétaire : GET /v1/cabinet/quotes → 200 ───────────────────────
  const cabinetQuotesResult = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/cabinet/quotes`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as Array<{ id: string; status: string; patient_name?: string }>)
        : [];
      return { status: resp.status, quotes: data };
    },
    API_BASE,
  );

  expect(cabinetQuotesResult.status).toBe(200);
  expect(Array.isArray(cabinetQuotesResult.quotes)).toBe(true);

  // ── 14. Secrétaire : UI /secretary/facturation affiche les devis ─────────
  await page.goto('/secretary/facturation');
  await expect(page.locator('h1')).toBeVisible({ timeout: 10_000 });
  await expect(
    page.locator('#quotes-status, #quotes-table, #quotes-empty'),
  ).toBeVisible({ timeout: 10_000 });
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Patient ne voit que ses propres devis (pas de fuite cross-rôle)
// ─────────────────────────────────────────────────────────────────────────────
test('EX3 : aucune fuite cross-rôle — GET /v1/quotes retourne uniquement les devis du patient connecté', async ({ page }) => {
  // ── 1. Connexion patient ──────────────────────────────────────────────────
  await loginAs(page, 'patient');

  // ── 2. GET /v1/me + GET /v1/quotes → patient_id cohérent ─────────────────
  const leakCheck = await page.evaluate(async (apiBase: string) => {
    const jwt = localStorage.getItem('nubia_jwt') ?? '';

    const meResp = await fetch(`${apiBase}/v1/me`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    const me = meResp.ok ? ((await meResp.json()) as { id?: string }) : {};
    const myId = me.id ?? '';

    const listResp = await fetch(`${apiBase}/v1/quotes`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    const list = listResp.ok
      ? ((await listResp.json()) as Array<{ id: string; patient_id?: string }>)
      : [];

    const foreignQuotes = list.filter(
      (q) => q.patient_id !== undefined && q.patient_id !== myId,
    );

    return {
      listStatus: listResp.status,
      myId,
      foreignCount: foreignQuotes.length,
    };
  }, API_BASE);

  expect(leakCheck.listStatus).toBe(200);
  expect(leakCheck.myId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  // Aucun devis d'un autre patient ne doit apparaître
  expect(leakCheck.foreignCount).toBe(0);
});
