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
