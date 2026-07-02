# 13 — Plan d'action : finir les 3 fronts Flutter

> Carte de route **courte et stable** (2026-07-02). L'état d'avancement vit dans les
> issues Forgejo + `git log` — ce fichier ne se coche pas, il ne liste que les
> chantiers et leur critère de fin. Registre QA : `qa/explored-paths.md`.

## Définition de « fini »

1. **0 issue P0/P1 ouverte** `scope:flutter-front`.
2. **Flows d'onboarding A/B/C verts** au run flutter-qa-agent (2 runs consécutifs sans nouvelle détection).
3. **Aucun stub navigable** : toute route déclarée rend une feature branchée (bloc → usecase → API réelle).
4. **Suite E2E Playwright** : les 5 parcours prioritaires de `front/docs/e2e-scenarios.md` passent en CI.
5. `melos run analyze` + `flutter test` verts sur les 3 apps (déjà exigé par la CI).

## État vérifié (2026-07-02)

- Architecture saine : blocs/cubits câblés en DI, usecases **réellement appelés**
  (vérifié sur dashboard/agenda/messaging/devis), 27 repos `nubia_data` branchés Dio.
- Login OK sur les 3 apps. Onboarding **C (praticien) corrigé** (#3194 + follow-ups),
  **B (secrétariat) corrigé** (#3187 via PR #3209) — tous deux en attente de confirmation
  au prochain run QA. **A (patient) toujours cassé** (#3100, #3022).
- Un seul stub routeur : `/ordonnances/new` (praticien, `NubiaEmptyState` en dur dans
  `app_router.dart:118`).
- Couverture tests réelle mais mince hors auth/register (~1-2 fichiers par feature).
- E2E : scénarios écrits (`front/docs/e2e-scenarios.md`), harness non implémenté.

## Phase 0 — Assainir le backlog QA (préalable, peu coûteux)

Le stock d'issues P0 `needs-split` date d'avant plusieurs fixes mergés ; une partie est
périmée (même schéma que #3192/#3196/#3198, fermées comme doublons).

- Re-tester chaque P0 `needs-split` contre `main` et **fermer les périmées** avec une
  ligne dans `qa/explored-paths.md` : #3190 (flow C, probablement doublon), #3079,
  #3092, #3039, #3046, #3056 (blank-canvas — l'ancienne famille était de faux positifs
  hash-routing), #3135 (navigation waiting-room).
- Découper celles qui restent réelles en issues atomiques `agent:go`.

## Phase 1 — P0 produit restants

| Chantier | App | Réfs |
| --- | --- | --- |
| Onboarding flow A : redirect `/account-setup` après signup | patient | #3100, #3022 ; `features/signup/` |
| Vérif QA post-merge flows B et C (aucun code attendu) | secrétariat, praticien | registre `qa/explored-paths.md` |

## Phase 2 — Combler les gaps fonctionnels

| Chantier | App | Réfs |
| --- | --- | --- |
| Feature-gap racine `/` | patient | #3199 |
| Feature-gap avis `/reviews` | patient | #3167 |
| Formulaire ordonnance réel sur `/ordonnances/new` (remplace le stub) | praticien | `router/app_router.dart:118`, `features/ordonnances/` |
| Consultation clinique : notes + actes CCAM + clôture bout-en-bout | praticien | `features/consultation_clinique/` |
| Onboarding secrétariat : bloc dédié (aujourd'hui page sans bloc) | secrétariat | `features/onboarding/` |

## Phase 3 — Filet de tests par feature

Un test bloc + un test widget par feature des parcours critiques (A1 booking, A4
waiting-room, B1 devis→signature, D3 messagerie), sur le modèle de
`register/pro_register_page_test.dart` (navigation post-succès incluse). Toute PR de
phase 1-2 embarque son test de non-régression — pas de rattrapage global en fin de course.

## Phase 4 — E2E Playwright (ordre de `front/docs/e2e-scenarios.md`)

1. Infra harness + fixtures (`loginAs`, seed déterministe) — bloque le reste.
2. A1 booking + confirmation. 3. A4 waiting-room temps réel (WS).
4. B1 wedge devis → signature → acompte. 5. D3 messagerie cabinet.
6. C1/C2 cloisonnement clinique/RLS (API + screenshot).

## Phase 5 — Stabilisation

Boucle flutter-qa-agent jusqu'à 2 runs consécutifs sans nouvelle P0/P1 sur les 3 apps,
puis gel : toute nouvelle détection redevient une issue classique.

## Gouvernance

- Découpage en issues : par le planner, depuis ce fichier ; 1 issue = 1 PR atomique.
- Ce document ne change que si un chantier s'ajoute ou disparaît — jamais pour du suivi.
