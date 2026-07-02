import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './scenarios',
  // _template est un modèle à copier, pas un test (ses credentials sont fictifs
  // et ses 401 en boucle épuisent le rate-limit login pour toute la suite).
  testIgnore: '**/_template.spec.ts',
  timeout: 90_000,
  globalTimeout: 15 * 60_000,
  // 1 retry : l'env de test déployé a une latence variable au premier rendu
  // post-login — un unique échec transitoire ne doit pas invalider le run.
  retries: 1,
  // Séquentiel : les scénarios partagent les comptes seed et le backend
  // rate-limite /auth/login (5/min par IP) — le parallélisme provoque des 429
  // en cascade. Voir aussi loginThrottle() dans fixtures/helpers.ts.
  workers: 1,
  reporter: [['list']],
  use: {
    headless: true,
    screenshot: 'only-on-failure',
    video: 'off',
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
});
