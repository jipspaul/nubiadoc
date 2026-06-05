# Nubia — racine du repo (router pour agents)

> Ce fichier est minimal : la connaissance fine vit dans les `AGENTS.md` par dossier.
> Tu n'as PAS besoin de tout lire — saute directement au `AGENTS.md` du dossier que tu touches.

## Routage par scope
- `api/` → backend Rust/Axum/SQLx → lis `api/AGENTS.md`.
- `app/` → app Flutter/Bloc → lis `app/AGENTS.md`.
- `db/` → schéma PostgreSQL (migrations + pgTAP) → lis `db/AGENTS.md`.
- `web-console/` → back-office Astro + Playwright → lis `web-console/AGENTS.md`.
- `design/` → specs UX, design system, copy, a11y → lis `design/AGENTS.md`.

## Règles transverses (s'appliquent partout)
1. **Forgejo** = source unique. Branche `main` protégée (1 review + CI verte).
2. **Sparse-checkout actif** : ton clone ne contient que les dossiers de ton scope (déclarés dans `.agents.yaml` racine). Si tu as besoin d'un fichier hors scope, dis-le dans la PR — n'essaie pas de l'éditer via sparse-checkout disable.
3. **POC/démo = données fictives uniquement.** Aucune PII réelle avant la barrière G3 (cf. `docs/07-conformite.md` §11).
4. **Commits en français, à l'impératif**, clairs (« Ajoute la route POST /v1/conversations »). Jamais « update »/« wip ».
5. **CI vert obligatoire** avant merge. La CI test-integrity bloque la suppression de tests / l'ajout de `#[ignore]`/`skip`.

## Contexte produit (court)
- Nubia = SaaS dentaire, multi-tenant (cabinet = tenant).
- Stack : Rust/Axum (api), Flutter/Bloc (app), Postgres/PostGIS (db), Astro (back-office).
- Conformité : RLS multi-tenant + chiffrement colonne (PII) + audit append-only **dès le départ**, non rétrofittables.
- Pas de fonction "dispositif médical".

## Pour aller plus loin (lecture optionnelle, gros fichiers)
- `PROGRESS.md` — état global + prochaines étapes.
- `docs/12-reference-api.md` — toutes les routes/contrats.
- `docs/05-donnees.md` — modèle de données.
- `docs/07-conformite.md` — règles RGPD/HDS.
- `INSTRUCTIONS_PROJET.md` — cadrage projet long-form (historique, à éviter sauf besoin spécifique).
