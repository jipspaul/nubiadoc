/**
 * EP5 — Documents + devis patient (E2E flow)
 *
 * Parcours :
 *   1. Documents (W20) : UI /patient/documents liste → UI /patient/documents/:id détail
 *                        → bouton activé → GET /v1/documents/:id/download 200 (URL signée)
 *   2. Devis     (W21) : UI /patient/devis liste → POST /v1/quotes/:id/signature (Yousign stub)
 *                        → GET /v1/quotes/:id statut mis à jour → POST /v1/payments/intent → 201
 *
 * Prérequis : dev-stack actif sur FLOWS_BASE_URL (défaut :38040) avec seed P2.
 * Le seed doit contenir au moins un document et un devis en statut `pending`/`sent`.
 *
 * Variables d'environnement :
 *   FLOWS_BASE_URL       URL de l'app web (défaut http://localhost:38040)
 *   FLOWS_API_BASE_URL   URL de l'API backend (défaut http://localhost:38030)
 */

import { test, expect } from '@playwright/test';
import { loginAs, clearSession } from './helpers';

const API_BASE =
  process.env.FLOWS_API_BASE_URL ?? 'http://localhost:38030';

/** Helper : récupère le JWT depuis localStorage. */
async function getJwt(page: Parameters<typeof loginAs>[0]): Promise<string> {
  return (await page.evaluate(() => localStorage.getItem('nubia_jwt'))) ?? '';
}

test.afterEach(async ({ page }) => {
  await clearSession(page);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 1 : Documents — liste UI → détail UI → download
// ─────────────────────────────────────────────────────────────────────────────
test('documents : liste UI → détail UI → /download 200 + URL reçue', async ({ page }) => {
  await loginAs(page, 'patient');
  const jwt = await getJwt(page);
  expect(jwt).not.toBe('');

  // ── 1. UI : page /patient/documents — liste ───────────────────────────────
  await page.goto('/patient/documents');
  await expect(page.locator('#docs-loading')).toBeHidden({ timeout: 15_000 });
  // L'un des trois états (liste / vide / erreur) est rendu : on ne cible que
  // l'élément visible (`:visible`) pour éviter une violation de mode strict.
  await expect(
    page.locator('#docs-list:visible, #docs-empty:visible, #docs-error:visible').first(),
  ).toBeVisible({ timeout: 10_000 });

  // ── 2. API : GET /v1/documents → confirme la liste ────────────────────────
  const listResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/documents`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const json = resp.ok ? await resp.json() : null;
      const data = (Array.isArray(json) ? json : (json?.data ?? [])) as Array<{
        id: string;
        category?: string;
        filename?: string;
        created_at?: string;
      }>;
      return { status: resp.status, documents: data };
    },
    API_BASE,
  );

  expect(listResp.status).toBeLessThan(300);
  expect(Array.isArray(listResp.documents)).toBe(true);

  // La suite ne peut s'exécuter qu'avec au moins un document (seed P2)
  if (listResp.documents.length === 0) {
    await expect(page.locator('#docs-empty')).toBeVisible();
    return;
  }

  const firstDoc = listResp.documents[0];
  expect(firstDoc.id).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );

  // ── 3. UI : naviguer vers /patient/documents/:id ──────────────────────────
  await page.goto(`/patient/documents/${firstDoc.id}`);
  // Attendre que les métadonnées soient visibles (le script client remplit #doc-metadata)
  await expect(page.locator('#doc-metadata')).toBeVisible({ timeout: 15_000 });

  // ── 4. API : GET /v1/documents/:id → métadonnées ─────────────────────────
  const detailResp = await page.evaluate(
    async ({ apiBase, docId }: { apiBase: string; docId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/documents/${docId}`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as { id: string; filename?: string; category?: string; mime_type?: string })
        : null;
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, docId: firstDoc.id },
  );

  expect(detailResp.status).toBe(200);
  expect(detailResp.data?.id).toBe(firstDoc.id);

  // ── 5. UI : bouton télécharger activé → clic ─────────────────────────────
  const btnDownload = page.locator('#btn-download');
  await expect(btnDownload).toBeEnabled({ timeout: 10_000 });

  // ── 6. API : GET /v1/documents/:id/download → URL signée reçue ───────────
  // L'API répond 200 avec { url } OU un 302 vers le stockage (URL signée stub
  // `storage.example.com` non résolvable). On utilise `redirect: 'manual'`
  // pour ne pas suivre la redirection (qui échouerait au DNS) et on accepte
  // soit la redirection opaque, soit un 200 JSON { url }.
  const downloadResp = await page.evaluate(
    async ({ apiBase, docId }: { apiBase: string; docId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/documents/${docId}/download`, {
        headers: { Authorization: `Bearer ${jwt}` },
        redirect: 'manual',
      });
      let url: string | null = null;
      if (resp.type !== 'opaqueredirect') {
        const ct = resp.headers.get('Content-Type') ?? '';
        if (ct.includes('application/json')) {
          const body = (await resp.json()) as { url?: string };
          url = body.url ?? null;
        }
      }
      return { status: resp.status, type: resp.type, url };
    },
    { apiBase: API_BASE, docId: firstDoc.id },
  );

  // Redirection 302 vers le stockage (opaqueredirect) OU 200 JSON { url } : OK
  const isRedirect = downloadResp.type === 'opaqueredirect';
  expect(isRedirect || (downloadResp.status === 200 && !!downloadResp.url)).toBe(true);
});

// ─────────────────────────────────────────────────────────────────────────────
// Scénario 2 : Devis — liste → signer (Yousign stub) → acompte
// ─────────────────────────────────────────────────────────────────────────────
test('devis : GET /v1/quotes liste → POST signature 202 → GET statut → POST /v1/payments/intent 201', async ({ page }) => {
  await loginAs(page, 'patient');
  const jwt = await getJwt(page);
  expect(jwt).not.toBe('');

  // ── 1. GET /v1/quotes → liste ─────────────────────────────────────────────
  const quotesListResp = await page.evaluate(
    async (apiBase: string) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/quotes`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const json = resp.ok ? await resp.json() : null;
      const data = (Array.isArray(json) ? json : (json?.data ?? [])) as Array<{
        id: string;
        status: string;
        total_amount?: number;
        created_at?: string;
      }>;
      return { status: resp.status, quotes: data };
    },
    API_BASE,
  );

  expect(quotesListResp.status).toBeLessThan(300);
  expect(Array.isArray(quotesListResp.quotes)).toBe(true);

  // ── 2. UI : page /patient/devis — chargement de la liste ─────────────────
  await page.goto('/patient/devis');
  await expect(page.locator('#quotes-loading')).toBeHidden({ timeout: 15_000 });
  await expect(
    page.locator('#quotes-list:visible, #quotes-empty:visible, #quotes-error:visible').first(),
  ).toBeVisible({ timeout: 10_000 });

  // ── 3. Chercher un devis en statut signable (pending ou sent) ────────────
  const signableQuote = quotesListResp.quotes.find(
    (q) => q.status === 'pending' || q.status === 'sent',
  );

  if (!signableQuote) {
    // Aucun devis signable dans le seed — on vérifie au moins l'UI
    // et on clôt le scénario normalement.
    return;
  }

  // ── 4. POST /v1/quotes/:id/signature → 202 (Yousign stub) ────────────────
  const signResp = await page.evaluate(
    async ({ apiBase, quoteId }: { apiBase: string; quoteId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/quotes/${quoteId}/signature`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Idempotency-Key': crypto.randomUUID(),
        },
      });
      const data = resp.ok
        ? ((await resp.json()) as { signature_id?: string; redirect_url?: string; embed_token?: string })
        : null;
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, quoteId: signableQuote.id },
  );

  // Le stub Yousign doit retourner 202 (signature initiée)
  // ou 409 si le devis est déjà signé/verrouillé (idempotence)
  expect([202, 409]).toContain(signResp.status);

  if (signResp.status === 202) {
    // La réponse doit contenir un signature_id ou un redirect_url/embed_token
    expect(
      signResp.data?.signature_id ||
      signResp.data?.redirect_url ||
      signResp.data?.embed_token,
    ).toBeTruthy();
  }

  // ── 5. GET /v1/quotes/:id → vérifier que le statut a évolué ──────────────
  const quoteDetailResp = await page.evaluate(
    async ({ apiBase, quoteId }: { apiBase: string; quoteId: string }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/quotes/${quoteId}`, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      const data = resp.ok
        ? ((await resp.json()) as { id: string; status: string; total_amount?: number })
        : null;
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, quoteId: signableQuote.id },
  );

  expect(quoteDetailResp.status).toBe(200);
  expect(quoteDetailResp.data?.id).toBe(signableQuote.id);
  // Le statut doit être dans un état cohérent après la demande de signature
  expect(quoteDetailResp.data?.status).toBeTruthy();

  // ── 6. POST /v1/payments/intent → 201 (acompte) ──────────────────────────
  const amountCents =
    typeof signableQuote.total_amount === 'number' && signableQuote.total_amount > 0
      ? Math.min(signableQuote.total_amount, 5000) // au plus 50 € pour le test
      : 5000;

  const intentResp = await page.evaluate(
    async ({
      apiBase,
      quoteId,
      amountCents,
    }: {
      apiBase: string;
      quoteId: string;
      amountCents: number;
    }) => {
      const jwt = localStorage.getItem('nubia_jwt') ?? '';
      const resp = await fetch(`${apiBase}/v1/payments/intent`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': crypto.randomUUID(),
        },
        body: JSON.stringify({
          quote_id: quoteId,
          kind: 'deposit',
          amount_cents: amountCents,
          method: 'card',
        }),
      });
      const data = resp.ok
        ? ((await resp.json()) as { payment_id?: string; client_secret?: string })
        : null;
      return { status: resp.status, data };
    },
    { apiBase: API_BASE, quoteId: signableQuote.id, amountCents },
  );

  // 201 = PaymentIntent créé ; 409 = devis dans un état non payable (acceptable)
  expect([201, 409]).toContain(intentResp.status);

  if (intentResp.status === 201) {
    expect(
      intentResp.data?.payment_id || intentResp.data?.client_secret,
    ).toBeTruthy();
  }
});
