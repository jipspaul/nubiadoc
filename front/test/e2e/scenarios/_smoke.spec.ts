/**
 * _smoke — Vérification de base du harnais E2E (3 rôles)
 *
 * Ce test est le guard minimal du harnais : si ce fichier passe, les fixtures
 * login.ts + helpers.ts + e2e.config.ts fonctionnent correctement.
 *
 * Chaque test :
 *   1. Ouvre une page isolée
 *   2. Lance loginAs(role, page) → active la sémantique Flutter + login form
 *   3. Vérifie que la route logique n'est plus /login (dashboard rendu)
 *   4. Logout (vidage du storage + reload → l'auth guard redirige vers /login)
 *
 * Navigation inter-pages : TOUJOURS via gotoRoute()/waitForRoutePrefix() des
 * fixtures — app_practicien route par pathname (usePathUrlStrategy) tandis que
 * patient/secretariat routent par fragment `#/...` (défaut Flutter web). Un
 * page.goto brut ou une assertion toHaveURL casse sur l'une ou l'autre app.
 *
 * Lancement : melos run e2e -- --grep _smoke
 * (ou: cd front/test/e2e && npx playwright test scenarios/_smoke.spec.ts)
 */

import { test, expect } from '@playwright/test';
import {
  loginAs,
  gotoRoute,
  currentRoute,
  waitForRoutePrefix,
  type Role,
} from '../fixtures/login';

const ROLES: Role[] = ['patient', 'practicien', 'secretariat'];

for (const role of ROLES) {
  test(`_smoke — ${role} : login → dashboard chargé → logout`, async ({ page }) => {
    // ── Login browser ──────────────────────────────────────────────────────
    await loginAs(role, page);

    // ── Dashboard chargé ──────────────────────────────────────────────────
    expect(await currentRoute(page, role)).not.toMatch(/^\/login/);

    // L'app a rendu du contenu sémantique au-delà du placeholder
    // d'accessibilité (l'arbre flt-semantics n'existe que si un frame a
    // été rendu avec la sémantique active).
    await expect(page.locator('flt-semantics').first()).toBeAttached({
      timeout: 10_000,
    });

    // ── Logout ─────────────────────────────────────────────────────────────
    // Vidage du storage puis reload : le RouterNotifier garde l'état auth en
    // mémoire, seul un reboot de l'app force restore() → plus de token →
    // l'auth guard redirige vers /login. (Un simple goto ne recharge pas les
    // apps en hash routing.)
    await page.evaluate(() => {
      localStorage.clear();
      sessionStorage.clear();
    });
    await page.reload();
    await waitForRoutePrefix(page, role, '/login');
  });
}

// Régression QA-20260627-15 : la page secretariat/messages apparaissait vide.
// Ce test valide la navigation in-app vers /messages + rendu non-vide.
test('_smoke — secretariat : /messages rendu (non blank)', async ({ page }) => {
  await loginAs('secretariat', page);
  await gotoRoute(page, 'secretariat', '/messages');
  await waitForRoutePrefix(page, 'secretariat', '/messages');
  await expect(page.locator('flt-semantics').first()).toBeAttached({
    timeout: 10_000,
  });
});
