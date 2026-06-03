# PROMPT — Construire la base de données Nubia (module `db/`)

> Prompt réutilisable, **adapté au projet Nubia** (SaaS dentaire / marketplace santé).
> Différences clés vs. le prompt générique d'origine : **SQLx** (pas dbmate), **migrations forward-only** (pas de `down`), **pas de Docker** (Postgres déjà présent dans l'environnement de l'agent), **CI Forgejo** (pas GitHub Actions), et une couche **multi-tenant RLS + chiffrement + audit** non négociable.
> À coller tel quel à l'agent qui écrit le SQL. Le **modèle de données** est `docs/05`, la **gouvernance** est `db/README.md`, le **plan des migrations** est `db/migrations/README.md`.

---

# RÔLE
Tu construis la base de données PostgreSQL de Nubia en tant que **LIVRABLE AUTONOME** et
versionné, dans le dossier `db/` de ce repo. Ce n'est PAS une partie de l'API : c'est un
module indépendant que d'autres agents (qui développent l'API Rust/Axum) vont seulement
**LANCER et CONSOMMER**, jamais modifier. Le schéma, les migrations, le seed et les tests
vivent dans `db/`.

Le dossier `db/` existe déjà en mode **spécification** (`README.md`, `migrations/README.md`,
`seed/README.md`). **Ta mission : écrire le SQL exécutable** qui réalise cette spec, plus les
tests qui en font le contrat. Tu ne réécris pas la gouvernance, tu l'implémentes.

# CONTRAINTES NON NÉGOCIABLES
- **PostgreSQL 16.**
- **Migrations versionnées avec SQLx** (SQL pur, indépendant du code applicatif). Fichiers
  `NNNN_description.sql`, numérotation 4 chiffres croissante, **immuables une fois mergés**.
  L'API pointe dessus via `sqlx migrate run --source db/migrations` — **un seul** répertoire
  de migrations dans tout le repo, c'est celui-ci.
- **Forward-only : PAS de `down`.** Sur du médical, les rollbacks ne sont pas fiables ; toute
  correction = **nouvelle migration**. (Convention actée, cf. `db/README.md` §2.)
- Les migrations doivent s'appliquer **FROM SCRATCH** sur une base vide, dans l'ordre, sans
  erreur, avec le rôle **`nubia_owner`**.
- On ne crée **JAMAIS** une table à la main : tout passe par une migration.
- **Pas de Docker / pas de docker-compose.** Les agents dev tournent **déjà dans un conteneur**
  qui dispose d'un **PostgreSQL 16 accessible** : le module ne déploie aucun conteneur, il
  s'applique sur une base existante désignée par `DATABASE_URL`. (Un Postgres local via
  `infra/poc/compose.yml` Podman reste possible côté humain, mais le module ne l'impose pas et
  n'en dépend pas.)
- Les **tests de la DB sont écrits en pgTAP (SQL)**. Ils sont **LE CONTRAT** de la base.
- **Seed 100 % déterministe** : aucun `random()`, aucun `now()`/`uuid` non gelé, aucune
  dépendance à l'ordre d'exécution. Mêmes données à chaque run, rejouable.
- Tout doit tourner via **UNE commande**, identique en local et en CI.

# MULTI-TENANT, SÉCURITÉ & AUDIT (cœur Nubia — à implémenter dès le départ)
Ces propriétés ne sont **pas rétrofittables**. Elles sont détaillées dans `db/README.md` §3-9
et `docs/07`. Tu les implémentes ET tu les couvres par des tests pgTAP.

- **Trois rôles distincts** (migration `0001`) :
  - `nubia_owner` — propriétaire du schéma, exécute le DDL (migrations). Jamais utilisé en runtime.
  - `nubia_app` — rôle applicatif runtime, **NOSUPERUSER + NOBYPASSRLS**. C'est sous CE rôle
    que la RLS est efficace, et **sous lui que tournent les tests d'isolation**.
  - `nubia_seed` — chargement du seed démo (données fictives), isolé.
- **Row-Level Security** sur **toute** table tenant (`cabinet_id`) :
  `ENABLE` **+ `FORCE` ROW LEVEL SECURITY**, policies `USING`/`WITH CHECK` bornées à
  `cabinet_id = current_setting('app.current_cabinet_id', true)::uuid`. Le `true` (missing_ok)
  rend la policy **fail-closed** : sans GUC positionné → `NULL` → aucune ligne visible.
  Le contexte est posé par transaction : `SET LOCAL app.current_cabinet_id = $1`.
- **Entités plateforme hors RLS cabinet** : `patient_account`, `account_guardianship`, annuaire
  public (`provider` listé, `establishment`, `specialty`, `medical_act`, `availability_slot`),
  `review` publié. **Ne pas** leur coller de policy `cabinet_id` ; visibilité par policy dédiée
  (`is_listed = true`, propriété du titulaire).
- **Audit append-only** : `audit_log` partitionné `RANGE (occurred_at)` (partitions mensuelles) ;
  `nubia_app` n'a **que `INSERT`** (pas d'`UPDATE`/`DELETE`) → append-only garanti par privilège.
- **Soft-delete** sur le médical (`deleted_at`), jamais de `DELETE` dur ni de cascade destructive.
- **Chiffrement colonne** : applicatif (`core/crypto`, clé par cabinet via KMS). La base stocke
  `*_ciphertext bytea` + `*_key_ref text` — **aucun** chiffrement fait en SQL ; le seed des champs
  sensibles ne court-circuite pas ce chemin (cf. `seed/README.md`).
- **Anti-double-booking** : `appointment` porte une contrainte d'exclusion
  `EXCLUDE USING gist (practitioner_id WITH =, tstzrange(starts_at, ends_at) WITH &&)
  WHERE status NOT IN ('cancelled','no_show')`.
- **Extensions** : `pgcrypto` (uuid), `citext` (emails), `pg_trgm` (recherche floue noms),
  `postgis` (géo marketplace). Pas de `pgvector`/TimescaleDB au MVP.

# STRUCTURE ATTENDUE
```
/db
  Makefile                  # migrate, seed, test, reset, lint, verify-rls  (PAS de `up` docker)
  /migrations               # migrations SQLx (SQL pur, NNNN_*.sql) — plan dans migrations/README.md
  /seed                     # données déterministes fictives (SQL + éventuel binaire `nubia` pour le chiffré)
  /tests                    # tests pgTAP (le contrat)
  README.md                 # gouvernance (existant) — ne pas réécrire
  SCHEMA.md                 # contrat pour les agents API (voir plus bas) — à créer
  .env.example              # DATABASE_URL d'exemple (app + owner)
```

# CE QUE LES TESTS pgTAP DOIVENT VÉRIFIER
Pour CHAQUE élément du modèle (`docs/05`) et de la gouvernance (`db/README.md`) :
- existence des tables, colonnes, types, valeurs par défaut ;
- présence des index et des clés (PK, FK), et **comportement des FK** (restrict / soft-delete,
  pas de cascade destructive sur le médical, comme spécifié) ;
- les contraintes **REJETTENT** bien les mauvaises valeurs (`NOT NULL`, `CHECK`, `UNIQUE`) ;
- la contrainte d'exclusion d'`appointment` **rejette** un chevauchement de créneau ;
- comportement des fonctions / triggers / vues s'il y en a (ex. partitions d'`audit_log`) ;
- que les migrations s'appliquent **from scratch** sur une base vide.
- **⭐ Tests RLS (les plus importants), exécutés sous le rôle `nubia_app`** :
  - sans `app.current_cabinet_id` positionné → **0 ligne** visible (fail-closed) ;
  - avec cabinet A positionné → on voit A, **jamais** B (non-fuite inter-cabinets) ;
  - écriture dans un autre tenant **refusée** par `WITH CHECK` ;
  - `nubia_app` ne peut **pas** `UPDATE`/`DELETE` sur `audit_log` (append-only) ;
  - les entités plateforme (`patient_account`, annuaire public) restent visibles **hors** contexte cabinet.
- **Garde-fou automatisable** : toute table portant `cabinet_id` **doit** avoir une policy RLS —
  un test liste les tables tenant sans policy et **échoue** s'il en trouve une.

# COMMANDES À FOURNIR (Makefile)
Toutes opèrent sur la base désignée par `DATABASE_URL` (déjà fournie par l'environnement de
l'agent). **Aucune** ne lance de conteneur.
- `make migrate`     : applique toutes les migrations (`sqlx migrate run --source db/migrations`, rôle **owner**).
- `make seed`        : charge le seed déterministe (rôle **seed**).
- `make test`        : reset → migrate → installe pgTAP → lance les tests pgTAP (`pg_prove`) **sous `nubia_app`** → reporte pass/fail.
- `make reset`       : détruit et recrée une base/schéma propre.
- `make lint`        : lint SQL (ex. `sqlfluff` dialecte postgres) + check « tables tenant sans policy ».
- `make verify-rls`  : (peut être inclus dans `test`) vérifie que `nubia_app` est bien NOSUPERUSER/NOBYPASSRLS et que la non-fuite tient.

`make test` doit tourner **tel quel** en CI. Fournis aussi le workflow **Forgejo**
`.forgejo/workflows/db.yml` (pas GitHub Actions) : il démarre/branche un service Postgres 16,
exporte `DATABASE_URL`, puis lance `make test`. Aligne-toi sur les workflows existants
(`.forgejo/workflows/flutter-test.yml`, `web-e2e.yml`).

# CONTRAT POUR LES AGENTS API (SCHEMA.md)
Rédige `db/SCHEMA.md` à destination des agents qui font l'API (Rust/Axum + SQLx) :
- **comment lancer la base** : pas de conteneur à déployer ; ils utilisent le Postgres de leur
  env et exportent `DATABASE_URL`, puis `make migrate` (ou `sqlx migrate run --source db/migrations`) ;
- les **deux** `DATABASE_URL` : runtime = **`nubia_app`** (toujours), migrations = `nubia_owner` (séparée, hors app) ;
- la liste des tables/colonnes/relations (peut référencer `docs/05` plutôt que dupliquer) ;
- le **contexte RLS** : ouvrir chaque transaction avec `SET LOCAL app.current_cabinet_id`, et le
  **réinjecter à chaque opération** sur WebSocket longue durée ;
- la **règle EXPLICITE** : les agents API **ne modifient jamais** le schéma ni les migrations ;
  tout besoin de changement de schéma = **nouvelle migration dans `db/`**, pas ailleurs, pas de
  table créée à la main, pas de second dossier de migrations dans `api/`.

# RÈGLES DE TRAVAIL
- Avance par **petites étapes** : une migration → ses tests pgTAP → tu fais passer au vert, puis
  la suivante. Respecte l'ordre `0001 → 0012` de `db/migrations/README.md`.
- **Ne modifie pas un test pour le faire passer** : c'est le contrat. Si un test est faux par
  rapport à la spec (`docs/05` / `db/README.md`), **signale-le à Xav, il tranche.**
- ⚠️ **Les commits sont faits par Xav** (le sandbox n'a pas les accès SSH). Toi : produis les
  fichiers, tiens `PROGRESS.md` à jour, et **signale quand c'est un bon moment de committer**
  (message suggéré impératif en français). Commite souvent (un fichier non commité peut être
  perdu au prochain reset/pull).
- **Démo/POC = données fictives uniquement.** Aucune donnée patient réelle avant la barrière G3
  (`docs/07` §11).
- À la fin, donne : la **commande unique** pour tout lancer, et la **preuve** que `make test`
  passe **from scratch**.

# SPÉCIFICATION (source de vérité)
**Le modèle de données EST `docs/05-modele-de-donnees.md`** — ne le réinvente pas, ne le duplique
pas. L'ordre, le contenu et la cartographie tables→migrations sont fixés dans
`db/migrations/README.md` (tableau `0001`→`0012`). Le seed cible est décrit dans `seed/README.md`.
La gouvernance (rôles, RLS, chiffrement, rétention, audit, index) est dans `db/README.md`.

Périmètre des migrations (résumé — détail dans `migrations/README.md`) :
`0001` extensions + rôles + grants · `0002` cabinet & identité · `0003` patient & clinique ·
`0004` documents · `0005` rendez-vous & file (+ EXCLUDE anti-double-booking) · `0006`
devis/signature/paiement · `0007` messagerie · `0008` audit & consentements (partitionné) ·
`0009` marketplace (annuaire/géo/avis) · `0010` extensions hi-fi (couverture, proches, journal,
plan, ordonnance **sans moteur d'interactions** — MDR, vérif RPPS, assistant) · `0011` policies
RLS (enable/force + policies + grants finaux) · `0012` index & contraintes d'exclusion.

> ⚠️ Rappel produit : **pas de fonction « dispositif médical »** (interactions médicamenteuses,
> aide à la décision) — `docs/07` §8. La base stocke/affiche passivement (allergies, etc.),
> aucun moteur de contrôle.
