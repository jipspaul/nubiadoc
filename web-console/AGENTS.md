# web-console/ — console admin (Astro + Playwright)

Tu es dans la **web-console Nubia** (back-office). Stack Astro + TypeScript + Playwright (E2E).

## Layout
- `src/` — pages Astro + composants.
  - `src/pages/` — routing file-based.
  - `src/components/` — composants réutilisables (`.astro` ou `.tsx` selon besoin d'interactivité).
- `tests/` — Playwright E2E (`*.spec.ts`).
- `scripts/` — helpers de build/dev.
- `astro.config.mjs` — config Astro (intégrations, output).
- `playwright.config.ts` — config E2E.
- `package.json` — versions épinglées (pas de `^`).

## Règles dures
1. **Pas de framework JS lourd** (React/Vue) sans justification : Astro server-first par défaut, hydratation seulement où nécessaire (`client:load`/`client:visible`).
2. **TypeScript strict** (`tsconfig.json` `strict: true`). Pas de `any` non justifié.
3. **Appels API** : via fetch typé (clients générés depuis `docs/12-reference-api.md` si possible), pas de fetch ad-hoc dans les composants.
4. **Auth** : passe par le même flow que l'app Flutter (JWT court + refresh). Jamais stocker le refresh-token en `localStorage` — `httpOnly cookie` côté serveur.
5. **Pas de PII dans les logs client.** Console.log = OK en dev, jamais commité avec PII.

## Tests
- E2E Playwright sur les flows critiques (login, création tenant, accès cross-tenant doit être bloqué).
- `npx playwright test` avant push.
- Tests unitaires composants : seulement si la logique est non-triviale (préférer E2E pour le reste).

## Avant de committer
- `npm run build` (vérifie le build prod)
- `npx playwright test`
- `npx tsc --noEmit` si tu as touché du `.ts`.

## Référence
- Routes API : `docs/12-reference-api.md`.
- Design tokens : `design/03-design-system/` (variables CSS exportables).
