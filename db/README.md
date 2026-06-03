# `db/` — Gestion de la base PostgreSQL (référence)

> **Source unique** de la couche données Nubia : migrations, rôles, policies RLS, seed démo. PostgreSQL 16 (Scaleway Managed **HDS** en prod, Podman en POC).
> **Statut : implémenté** — le SQL exécutable est écrit (`migrations/0001→0012`, `tests/` pgTAP, `seed/seed.sql`, `Makefile`, `SCHEMA.md`). `make test` passe **from scratch** (118 tests pgTAP sous `nubia_app`). Ce README porte la gouvernance ; le *quoi* reste `../docs/05`.
> **Modèle de données = `../docs/05-modele-de-donnees.md`** (entités, DDL de référence). Ce README porte la **gouvernance** : rôles, RLS, chiffrement, rétention, audit, runbook. Conformité : `../docs/07`. Archi/ADR : `../docs/04`.

## 1. Rôle du dossier & articulation
- `db/` est la **source unique** des migrations. L'API (workspace Cargo) **pointe dessus** : `sqlx migrate run --source ../db/migrations` (ou `DATABASE_MIGRATIONS=../db/migrations`). Pas de second répertoire de migrations dans `api/`.
- **`docs/05`** = le *quoi* (schéma logique, DDL de référence). **`db/`** = le *comment* (gouvernance + futurs fichiers SQL exécutables).
- **SQLx** : requêtes vérifiées à la compilation (`sqlx::query!`) ; les migrations sont du **SQL pur**, **forward-only**, versionnées ici.

```
db/
├── README.md            ← ce fichier (gouvernance DB)
├── migrations/          ← migrations SQLx (SQL pur, numérotées) — à écrire
│   └── README.md        ← plan & ordre des migrations
└── seed/                ← données démo FICTIVES (jamais de PII réelle)
    └── README.md        ← contenu du jeu de démo
```

## 2. Conventions
- **Nommage** : tables/colonnes `snake_case` **singulier** (`patient`, `clinical_note`). Migrations : `NNNN_description.sql` (préfixe numérique croissant, ex. `0003_patient_clinical.sql`), **immuables une fois mergées** (toute correction = nouvelle migration).
- **Forward-only** : pas de rollback automatique en prod (les `down` ne sont pas fiables sur du médical). Une erreur se corrige par une migration corrective.
- **Idempotence défensive** : `CREATE EXTENSION IF NOT EXISTS`, `CREATE TABLE IF NOT EXISTS` à éviter sur le métier (on veut l'échec si rejeu), mais utile sur extensions/roles. À trancher par migration.
- **Clés** : `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`. **Tenant** : `cabinet_id uuid NOT NULL REFERENCES cabinet(id)` sur quasi toutes les tables métier.
- **Temps** : `created_at`/`updated_at`/`deleted_at` en `timestamptz` UTC.
- **Argent** : `numeric(12,2)` + `currency char(3)` (jamais de float). L'API expose en **centimes entiers** (`../docs/12` §1.1) ; conversion à la frontière applicative.
- **Énums** : `text` + `CHECK` (souple, pas de migration de type) **ou** `ENUM` natif — au choix du module, documenté.
- **Pas de cascade destructive** sur le médical : **soft-delete** (`deleted_at`), jamais de `DELETE` dur.

## 3. Rôles PostgreSQL & privilèges (⭐ critique pour la RLS)
La RLS n'est efficace **que** sous un rôle **non-superuser qui ne bypass pas** la sécurité. Trois rôles distincts :

| Rôle | Usage | Privilèges |
|---|---|---|
| `nubia_owner` | **Propriétaire** du schéma : exécute les **migrations** (DDL). | `CREATE`/`ALTER`/`DROP`. **Jamais** utilisé par l'app runtime. |
| `nubia_app` | **Rôle applicatif runtime** (API + worker). | `SELECT/INSERT/UPDATE` sur le métier ; **`INSERT` seul** sur `audit_log` (append-only) ; **NOSUPERUSER**, **`NOBYPASSRLS`**. |
| `nubia_seed` | Chargement du **seed démo** (données fictives). | Écriture, isolé ; **jamais en prod sur données réelles**. |

Règles :
- L'app se connecte **toujours** en `nubia_app` (vérifié en CI). Se connecter en `postgres`/owner **désactiverait de fait la RLS** → interdit en runtime.
- `audit_log` : `GRANT INSERT` uniquement à `nubia_app` (pas d'`UPDATE`/`DELETE`) → **append-only garanti par privilège** (`../docs/05` §6, `../docs/07` §2.9).
- Les migrations et le seed s'exécutent avec un **rôle dédié explicite**, jamais `nubia_app`.

## 4. Multi-tenant — Row-Level Security (ADR-003)
Isolation **au niveau base**. Chaque requête applicative ouvre sa transaction avec le contexte du cabinet courant (issu du **JWT**, jamais du client) :

```sql
-- positionné par core/tenancy au début de CHAQUE transaction (paramétré)
SET LOCAL app.current_cabinet_id = $1;
```
Conventions de policy (par table tenant) :
- `ENABLE ROW LEVEL SECURITY` **+ `FORCE ROW LEVEL SECURITY`** (s'applique même au propriétaire de la table).
- `USING (cabinet_id = current_setting('app.current_cabinet_id', true)::uuid)` — le **`true`** (missing_ok) rend la policy **fail-closed** : si le GUC n'est pas positionné, `current_setting` renvoie `NULL` → aucune ligne visible.
- Policy d'écriture avec **`WITH CHECK`** aux mêmes bornes (empêche d'écrire dans un autre tenant).
- **Cloisonnement praticien/secrétariat** (R.4127-72) = **RBAC applicatif** *au-dessus* de la RLS (la RLS isole le cabinet ; le RBAC isole les rôles dans le cabinet, cf. `../docs/12` §1.3).
- ⚠️ **WebSocket longue durée** : réinjecter `SET LOCAL` à **chaque** opération DB, pas qu'à l'ouverture (`../docs/03`, `../docs/05` §2).

Entités **plateforme hors RLS cabinet** : `patient_account`, `account_guardianship`, annuaire public (`provider` listé, `establishment`, `specialty`, `medical_act`, `availability_slot` ouverts), `review` publié. Leur visibilité est gérée par policy dédiée (`is_listed = true`, propriété du titulaire), pas par `cabinet_id`.

## 5. Chiffrement colonne (données de santé)
Au-delà du chiffrement disque managé, chiffrement **applicatif** (module `core/crypto`), **une clé par cabinet** dérivée via **KMS** (Scaleway Key Manager). Stocké en `bytea` + référence de clé :
```sql
content_ciphertext bytea NOT NULL,
content_key_ref    text  NOT NULL,   -- version de clé du cabinet (KMS)
```
Chiffrés : INS / n° sécu, contenu `clinical_note`, `medical_record` (antécédents/allergies/traitements), contenu `message`, transcript Scribe (post-MVP), documents (Object Storage + URLs signées). Le chiffrement se fait **dans l'app avant écriture** (clé hors base) → pas de full-text sur le chiffré (la recherche porte sur du non-sensible). Détail : `../docs/05` §3, `../docs/07` §4.3.

## 6. Rétention, soft-delete & purge
- **Soft-delete obligatoire** sur le médical (`deleted_at`, filtré par défaut `WHERE deleted_at IS NULL`).
- **Dossier patient** : 20 ans après dernière consultation ; **30 ans pour les mineurs** (à partir de la majorité).
- **`audit_log`** : **≥ 10 ans**, append-only, partitionné par mois.
- **Audio Scribe** (post-MVP) : suppression sous **7 jours** sauf opt-in.
- **Purge** : job planifié **apalis** marque/purge selon politique, en **journalisant chaque purge** dans l'audit. Référence : `../docs/05` §4, `../docs/07`.

## 7. Audit & append-only
- `audit_log` : `bigint GENERATED ALWAYS AS IDENTITY`, **partitionné `RANGE (occurred_at)`** (partitions mensuelles), `metadata jsonb` **sans PII en clair**. `nubia_app` n'a que `INSERT`.
- Tout accès/écriture sur donnée de santé → une entrée (`read_record`, `update_quote`, `sign`, `login`, `purge`…). Voir matrice d'actions dans `../docs/12` (par route).
- `consent_record` : consentements **tracés et révocables** (`purpose`, `granted`, `revoked_at`, `evidence`).

## 8. Index & performance
- **Index tenant systématique** : `(cabinet_id, …)` en tête des index composites.
- `appointment` : `(cabinet_id, practitioner_id, starts_at)` + **contrainte d'exclusion** anti-double-booking (`EXCLUDE USING gist` sur `tstzrange`, hors `cancelled/no_show`).
- `document` : `(cabinet_id, patient_id, category)`. `message` : `(conversation_id, created_at)` + partiel `WHERE triage_flag='urgent'`. `quote` : `(cabinet_id, status)`.
- Recherche floue noms patients : **`pg_trgm`** (GIN sur champ non sensible). Annuaire/marketplace : **PostGIS** (`gist` sur `geography`) + **Meilisearch** hors base.

## 9. Extensions requises
`pgcrypto` (ou natif) pour `gen_random_uuid()` · `citext` (emails) · `pg_trgm` (recherche floue) · **`postgis`** (géo marketplace). `pgvector`/TimescaleDB **non installés** au MVP (`../docs/01` §3.3).

## 10. Runbook migrations
1. **Créer** : ajouter `db/migrations/NNNN_xxx.sql` (numéro suivant). Une migration = un objectif cohérent (cf. plan dans `migrations/README.md`).
2. **Appliquer en local** (POC Podman) :
   ```bash
   # DB up via Podman (depuis la racine) :
   podman-compose -f infra/poc/compose.yml up -d postgres
   # appliquer (rôle owner) :
   sqlx migrate run --source db/migrations            # DATABASE_URL = …nubia_owner@…
   ```
3. **CI** : appliquer les migrations en `nubia_owner`, puis **lancer la suite de tests RLS sous `nubia_app`** (rôle non-superuser) — c'est le test de non-fuite inter-cabinets (`../tests/`, `../docs/08`).
4. **Prod** : migrations jouées en fenêtre contrôlée, **jamais** `--force`/`DROP` destructeur sans validation (`CLAUDE.md` règles git/db). Sauvegarde + test de restauration avant (G3, `../docs/07` §1.6).
5. **Vérif RLS post-migration** : toute nouvelle table tenant **doit** avoir `ENABLE/FORCE RLS` + policies dans la même migration (ou la migration RLS dédiée) — sinon fuite. Check automatisable en CI (lister les tables avec `cabinet_id` sans policy).

## 11. Seed démo
- **Données fictives uniquement** (Cabinet Lyon, Dr Marin/Lefèvre, patients fictifs). **Aucune PII réelle avant la barrière G3** (`../docs/07` §11). Détail : `seed/README.md`.
- Chargé via `nubia_seed`, idempotent (truncate+insert ou upsert), utilisé pour la démo investisseurs et les tests e2e.

## 12. Environnements
| Env | Hébergement | Rôles | Notes |
|---|---|---|---|
| **Local / POC** | Podman (`infra/poc/compose.yml`) | owner + app + seed locaux | données fictives ; pas HDS. |
| **Staging** | Scaleway | idem, secrets gérés | proche prod, données fictives. |
| **Prod** | Scaleway **Managed HDS** | owner (migrations) / app (runtime) | barrière G3 obligatoire (`../docs/07` §11) ; sauvegardes chiffrées + PRA testé. |
- `DATABASE_URL` runtime pointe **toujours** sur `nubia_app`. L'URL owner (migrations) est séparée et n'est pas dans l'app.

## 13. Cartographie tables → migrations (plan)
Ordre prévu des fichiers (le SQL est à écrire ; ancré sur `../docs/05`) — détaillé dans `migrations/README.md` :
`0001` extensions + rôles + grants · `0002` cabinet & identité · `0003` patient & clinique · `0004` documents · `0005` rendez-vous & file · `0006` devis/signature/paiement · `0007` messagerie · `0008` audit & consentements (partitionné) · `0009` marketplace (annuaire/géo/avis) · `0010` extensions hi-fi (couverture, proches, journal, plan, ordonnance, vérif RPPS, assistant) · `0011` policies RLS (enable/force + policies + grants) · `0012` index & contraintes d'exclusion.

## 14. Checklist avant 1ʳᵉ donnée réelle (G3)
Reprend `../docs/07` §11 côté données : **HDS** contractualisé · **chiffrement colonne + RLS + audit append-only** effectifs et **testés** · rôle `nubia_app` non-superuser vérifié · **sauvegardes + test de restauration** · scrubbing des logs (zéro PII). Tant que rouge : démo (données fictives) OK, **prod NON**.

> Modèle complet : `../docs/05`. Contrats d'API consommateurs : `../docs/12`. Conformité : `../docs/07`. Plan de tests (dont RLS) : `../docs/08`.

<!-- trigger CI to verify db-ci:stable now available in DinD -->
# retrigger after db-ci rebuild with Node 22
