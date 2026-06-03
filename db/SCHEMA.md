# `db/SCHEMA.md` — Contrat pour les agents API (Rust / Axum + SQLx)

> **Public visé** : les agents/devs qui construisent l'API. Ce document dit **comment
> consommer** la base. Le *quoi* (entités/colonnes) est dans `../docs/05-modele-de-donnees.md` ;
> la *gouvernance* (rôles, RLS, chiffrement, rétention) dans `README.md` ; le *plan des
> migrations* dans `migrations/README.md`. **`db/` est la source unique des migrations.**

---

## 0. Règle d'or (à lire en premier)
- Les agents API **ne modifient JAMAIS** le schéma ni les migrations. Tout besoin de
  changement de schéma = **nouvelle migration dans `db/migrations/`** (numéro suivant,
  forward-only, immuable une fois mergée). **Pas** de table créée à la main, **pas** de
  second dossier de migrations dans `api/`.
- L'app se connecte **toujours** en `nubia_app` (NOSUPERUSER, NOBYPASSRLS). Se connecter en
  `postgres`/owner **désactiverait la RLS** → interdit en runtime.

---

## 1. Lancer la base (aucun conteneur à déployer)
La base n'embarque **aucun** conteneur : on s'applique sur le **PostgreSQL 16 déjà présent**
dans votre environnement (le dev container en fournit un ; en POC humain, `infra/poc/compose.yml`
Podman peut en fournir un, mais ce module n'en dépend pas).

```bash
cd db
cp .env.example .env            # adapter host/port si besoin
export $(grep -v '^#' .env | xargs)   # ou laisser le Makefile prendre ses défauts

make reset      # (admin) (re)crée base + rôle owner + extension postgis (untrusted)
make migrate    # (owner) applique toutes les migrations : sqlx migrate run --source migrations
make seed       # (seed)  charge le jeu démo fictif (optionnel)
make test       # reset+migrate+pgTAP puis tests RLS sous nubia_app  ← le contrat
```

Côté API, l'équivalent direct de `make migrate` :
```bash
sqlx migrate run --source ../db/migrations   # DATABASE_URL = …nubia_owner@…
```

---

## 2. Les DEUX `DATABASE_URL` (ne pas les confondre)
| Usage | Rôle | Variable | Quand |
|---|---|---|---|
| **Runtime API + worker** | `nubia_app` | `APP_DATABASE_URL` | **toujours** en service (RLS effective) |
| **Migrations (DDL)** | `nubia_owner` | `DATABASE_URL` | au déploiement/CI, **hors** application |
| Seed démo | `nubia_seed` | `SEED_DATABASE_URL` | données fictives uniquement |

> `nubia_app` est **NOSUPERUSER + NOBYPASSRLS** : c'est la condition pour que la RLS isole les
> cabinets. Vérifié par `make verify-rls` et par les tests pgTAP (`tests/03_rls.sql`).

---

## 3. Contexte RLS — **obligatoire à chaque transaction**
Toute requête applicative ouvre sa transaction en posant le cabinet courant (issu du **JWT**,
**jamais** du client) :

```sql
SET LOCAL app.current_cabinet_id = $1;   -- $1 = cabinet_id du token
```

Côté Rust/SQLx, encapsuler dans le helper `core/tenancy` (cf. `docs/04`) :
```rust
// pseudo-code
let mut tx = pool.begin().await?;
sqlx::query("SET LOCAL app.current_cabinet_id = $1")
    .bind(cabinet_id).execute(&mut *tx).await?;
// … toutes les requêtes du même tx voient UNIQUEMENT ce cabinet …
tx.commit().await?;
```

- **Fail-closed** : sans GUC positionné, `current_setting('app.current_cabinet_id', true)` vaut
  `NULL` → **0 ligne** visible et **0 écriture** possible. Ne comptez jamais là-dessus comme
  filtre « par défaut » : posez **toujours** le contexte.
- ⚠️ **WebSocket longue durée** : `SET LOCAL` est **transactionnel**. Réinjectez-le à **chaque**
  opération DB, pas seulement à l'ouverture de la socket (`docs/03`, `docs/05` §2).
- **RBAC** (praticien vs secrétariat, R.4127-72) est une couche applicative **au-dessus** de la
  RLS : la RLS isole le cabinet, le RBAC isole les rôles **dans** le cabinet (`docs/12` §1.3).

### Entités hors RLS cabinet (plateforme)
`patient_account`, `account_guardianship`, annuaire public (`provider` *listé*, `establishment`,
`profession`, `specialty`, `medical_act`, `availability_slot`), `review`, `app_user`.
→ Pas de `cabinet_id` à poser ; visibilité gérée par l'API/RBAC (et, pour `provider`, par la
policy `is_listed = true`). Le **clinique** (`medical_record`, `clinical_note`, `message`) reste
**strictement tenant** : la marketplace ne l'expose jamais.

---

## 4. Conventions que l'API doit respecter
- **Chiffrement colonne = applicatif** (`core/crypto`, clé par cabinet via KMS). La base stocke
  `*_ciphertext bytea` + `*_key_ref text`. **Chiffrez avant écriture**, déchiffrez après lecture ;
  ne mettez **jamais** de clair dans `*_ciphertext`. Champs concernés : INS/n° sécu, contenu
  `clinical_note`, `medical_record`, `message` (cf. `docs/05` §3). Pas de full-text sur le chiffré.
- **Argent** : colonnes `numeric(12,2)` + `currency char(3)`. L'API expose en **centimes entiers**
  (`docs/12` §1.1) ; conversion à la frontière.
- **Soft-delete** : filtrez `WHERE deleted_at IS NULL` ; ne faites **jamais** de `DELETE` dur sur
  le médical.
- **Audit append-only** : `nubia_app` peut **INSÉRER** dans `audit_log`, jamais `UPDATE`/`DELETE`
  (garanti par privilège). Tracez les accès/écritures sensibles (matrice par route : `docs/12`).
- **Anti-double-booking** : l'`INSERT`/`UPDATE` d'`appointment` peut lever une violation de
  contrainte d'exclusion (SQLSTATE `23P01`) → mappez-la en **`409 slot_taken`** (`docs/12` §7).
- **Idempotence paiements** : `payment.idempotency_key` (cf. `docs/12` §1.2).

---

## 5. Tables (référence)
Liste complète des tables/colonnes/relations : **`../docs/05-modele-de-donnees.md`** (ne pas
dupliquer ici). Cartographie tables → fichiers de migration : `migrations/README.md`.

Résumé des domaines : identité/cabinet (`0002`) · patient & clinique (`0003`) · documents
(`0004`) · agenda & file (`0005`) · wedge devis/signature/paiement (`0006`) · messagerie (`0007`)
· audit & consentements partitionnés (`0008`) · marketplace annuaire/géo/avis (`0009`) ·
extensions hi-fi couverture/proches/journal/plan/ordonnance/RPPS/assistant (`0010`) · policies
RLS (`0011`) · index (`0012`).

> ⚠️ **Pas de fonction « dispositif médical »** (interactions médicamenteuses, aide à la décision)
> — `docs/07` §8. La base **stocke/affiche passivement** (allergies, ordonnance) ; **aucun** moteur
> de contrôle. L'`assistant_query` est **organisationnel** (post-traction), journalisé.
