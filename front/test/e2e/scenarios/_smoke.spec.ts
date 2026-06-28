/**
 * _smoke — Vérification de base du harnais E2E (3 rôles)
 *
 * Ce test est le guard minimal du harnais : si ce fichier passe, les fixtures
 * login.ts + helpers.ts + e2e.config.ts fonctionnent correctement.
 *
 * Chaque test :
 *   1. Ouvre une page isolée
 *   2. Lance loginAs(role, page) → attend que le dashboard soit chargé
 *   3. Vérifie que l'URL n'est plus /login (dashboard effectivement rendu)
 *   4. Logout (vidage du storage + navigation vers /login → redirigé par l'auth guard)
 *
 * Navigation inter-pages : TOUJOURS via page.goto(url) — l'app utilise le path
 * routing go_router. Ne jamais modifier location.hash directement (go_router
 * l'ignore ; la page resterait sur la vue courante → faux positif « blank canvas »).
 *
 * Lancement : melos run e2e -- --grep _smoke
 * (ou: cd front/test/e2e && npx playwright test scenarios/_smoke.spec.ts)
 */

import { test, expect } from '@playwright/test';
import { loginAs, baseUrlFor, type Role } from '../fixtures/login';

const ROLES: Role[] = ['patient', 'practicien', 'secretariat'];

for (const role of ROLES) {
  test(`_smoke — ${role} : login → dashboard chargé → logout`, async ({ page }) => {
    // ── Login browser ──────────────────────────────────────────────────────
    await loginAs(role, page);

    // ── Dashboard chargé ──────────────────────────────────────────────────
    // loginAs a déjà attendu waitForURL(**) — on vérifie qu'on n'est plus sur /login
    await expect(page).not.toHaveURL(/\/login/);

    // Vérification minimale : l'app a rendu un élément de navigation principal
    // (nav rail desktop ou drawer mobile, selon le breakpoint du browser headless)
    await expect(
      page.getByRole('navigation').or(page.locator('nav, [role="navigation"]')).first(),
    ).toBeVisible({ timeout: 10_000 });

    // ── Logout ─────────────────────────────────────────────────────────────
    // On vide le storage côté browser (équivalent déconnexion).
    // L'auth guard Flutter redirige automatiquement vers /login à la prochaine
    // navigation, ce qui valide que la session est bien supprimée.
    await page.evaluate(() => {
      localStorage.clear();
      sessionStorage.clear();
    });

    const baseUrl = baseUrlFor(role);
    await page.goto(`${baseUrl}/`);
    await page.waitForURL(`${baseUrl}/login`, { timeout: 10_000 });
    await expect(page).toHaveURL(/\/login/);
  });
}

// Régression QA-20260627-15 : la page secretariat/messages apparaissait vide
// quand le QA-agent naviguait via location.hash au lieu de page.goto().
// go_router (path routing) ignore les changements de hash → canvas blanc.
// Ce test valide la navigation par URL complète.
test('_smoke — secretariat : /messages rendu via page.goto (non blank)', async ({ page }) => {
  await loginAs('secretariat', page);
  await page.goto(`${baseUrlFor('secretariat')}/messages`);
  await page.waitForLoadState('networkidle');
  await expect(page).toHaveURL(/\/messages/);
  await expect(
    page.getByRole('navigation').or(page.locator('nav, [role="navigation"]')).first(),
  ).toBeVisible({ timeout: 10_000 });
});
