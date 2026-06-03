# `db/migrations/` — Plan des migrations (à écrire)

> Migrations **SQLx** (SQL pur, forward-only, numérotées `NNNN_description.sql`). **Source unique** : l'API applique via `sqlx migrate run --source db/migrations`.
> **Statut : spécification.** Le SQL n'est pas encore écrit — ce fichier fixe l'ordre, le contenu et les règles de chaque migration. DDL de référence = `../../docs/05-modele-de-donnees.md`.

## Règles
- **Forward-only**, fichiers **immuables une fois mergés** (correction = nouvelle migration).
- Une migration = **un objectif cohérent** ; appliquée par `nubia_owner`, jamais par `nubia_app`.
- Toute table **tenant** (`cabinet_id`) doit recevoir `ENABLE`/`FORCE RLS` + policies — soit dans sa migration, soit dans `0011` (mais alors `0011` est **bloquante** avant tout runtime).
- Numérotation à 4 chiffres, pas de trou volontaire.

## Ordre prévu
| Fichier | Contenu | Réf. `docs/05` |
|---|---|---|
| `0001_extensions_roles.sql` | Extensions (`pgcrypto`, `citext`, `pg_trgm`, `postgis`) ; rôles `nubia_owner` / `nubia_app` (NOSUPERUSER, NOBYPASSRLS) / `nubia_seed` ; grants de base. | §2, §3, db/README §3, §9 |
| `0002_cabinet_identity.sql` | `cabinet`, `app_user`, `cabinet_membership`, `practitioner`. | §5.1 |
| `0003_patient_clinical.sql` | `patient`, `medical_record`, `clinical_note`, `dental_chart`. | §5.2 |
| `0004_documents.sql` | `document` (catégories : devis, facture, ordonnance, radio, cbct, photo, cr, consigne, attestation, carte_mutuelle, passeport_implantaire, consentement). | §5.3, §10.9 |
| `0005_scheduling.sql` | `appointment` (+ **EXCLUDE gist** anti-double-booking), `checkin_event`, `waiting_list_entry`. | §5.4 |
| `0006_billing.sql` | `quote`, `quote_item`, `signature`, `payment_schedule`, `payment`. | §5.5 |
| `0007_messaging.sql` | `conversation`, `message` (`triage_flag`). | §5.6 |
| `0008_audit_consent.sql` | `audit_log` **partitionné RANGE(occurred_at)** (partitions mensuelles, `INSERT`-only pour `nubia_app`), `consent_record`. | §6 |
| `0009_marketplace.sql` | `patient_account` (+ lien `patient.patient_account_id`), `profession`, `specialty`, `medical_act`, `establishment`, `provider`, `availability_slot`, `review`. | §9 |
| `0010_hifi_extensions.sql` | Couverture (`patient_account`: `regime_obligatoire`, `nss_ciphertext`, `tiers_payant`) ; `account_guardianship` ; `clinical_note` (`note_kind`, `tooth`, `act_ref`) ; `treatment_plan`, `treatment_phase`, `quote_item.phase_id` ; `prescription`, `prescription_item` ; `provider_verification` ; `assistant_query`. | §10 |
| `0011_rls_policies.sql` | `ENABLE`/`FORCE ROW LEVEL SECURITY` + policies `tenant_isolation`/`tenant_write` (fail-closed `current_setting(...,true)`) sur **toutes** les tables tenant ; policies de visibilité publique (annuaire `is_listed`, `review` publié) ; grants finaux (`audit_log` = INSERT seul). | §2, §9.3, db/README §3-4 |
| `0012_indexes.sql` | Index composites tenant-first ; `pg_trgm` (noms patients) ; `gist` PostGIS (`provider.geo`) ; index partiels (`message` urgents) ; `(cabinet_id, status)` devis, etc. | §8 |

## Points de vigilance par migration
- **`0001`** : sans `nubia_app` non-superuser + `NOBYPASSRLS`, la RLS est inopérante (cf. db/README §3). À tester en CI.
- **`0005`** : la contrainte d'exclusion (`EXCLUDE USING gist (practitioner_id WITH =, tstzrange(starts_at, ends_at) WITH &&) WHERE status NOT IN ('cancelled','no_show')`) garantit l'absence de double-booking côté DB → l'API mappe le conflit en `409 slot_taken` (`../../docs/12` §7).
- **`0008`** : prévoir la **création automatique des partitions mensuelles** (job apalis ou `pg_partman` à évaluer).
- **`0009`/`0010`** : `patient_account` et `account_guardianship` sont **hors RLS cabinet** (entités plateforme) → ne pas leur coller de policy `cabinet_id`.
- **`0011`** : checklist « toute table à `cabinet_id` a une policy » à automatiser (requête de contrôle en CI). Chiffrement colonne = applicatif (`core/crypto`), **pas** d'extension SQL.

> Après écriture : `sqlx migrate run --source db/migrations` (rôle owner) puis suite de tests RLS sous `nubia_app` (`../../tests/`, `../../docs/08`).
