# 05 — Modèle de données

> Schéma de la base PostgreSQL 16 (Scaleway Managed HDS) : entités, relations, multi-tenant par RLS, chiffrement colonne, rétention/soft-delete, champs JSONB. Aligné sur `04-architecture.md`.
> Les DDL sont des **esquisses de référence** (pas le schéma final exécutable) : types et contraintes y sont indicatifs.

## Sommaire
1. Conventions
2. Multi-tenant & RLS
3. Chiffrement colonne
4. Rétention & soft-delete
5. Entités (par domaine)
6. Audit & consentements
7. Champs JSONB
8. Index & performance

---

## 1. Conventions
- **Clés** : `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`.
- **Tenant** : `cabinet_id UUID NOT NULL REFERENCES cabinet(id)` sur quasi toutes les tables.
- **Horodatage** : `created_at`, `updated_at` (`timestamptz`, UTC), `deleted_at` (soft-delete, nullable).
- **Nommage** : tables et colonnes en `snake_case` singulier (`patient`, `clinical_note`).
- **Énumérations** : types PostgreSQL `ENUM` ou `text` + `CHECK` (au choix module).
- **Argent** : `numeric(12,2)` + `currency char(3)` (jamais de float).
- **Pas de cascade destructive** sur le médical : on soft-delete, on n'efface pas.

---

## 2. Multi-tenant & Row-Level Security

Décision ADR-003 : isolation au niveau base. Chaque requête applicative ouvre sa transaction avec le contexte du cabinet courant.

```sql
-- positionné par core/tenancy au début de chaque transaction
SET LOCAL app.current_cabinet_id = '<uuid-du-cabinet-du-token>';

-- activation RLS (exemple sur patient)
ALTER TABLE patient ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON patient
  USING (cabinet_id = current_setting('app.current_cabinet_id')::uuid);

-- variante pour le rôle d'écriture (mêmes bornes en WITH CHECK)
CREATE POLICY tenant_write ON patient
  FOR ALL
  USING (cabinet_id = current_setting('app.current_cabinet_id')::uuid)
  WITH CHECK (cabinet_id = current_setting('app.current_cabinet_id')::uuid);
```

**Règles**
- Le `cabinet_id` n'est **jamais** accepté depuis le client : il vient du JWT.
- Le rôle applicatif Postgres n'est **pas** superuser et ne bypass pas la RLS.
- Cloisonnement praticien/secrétariat (R.4127-72) = couche **RBAC applicative** *au-dessus* de la RLS (la RLS isole le cabinet, le RBAC isole les rôles dans le cabinet).
- Les migrations et le seed `demo` s'exécutent avec un rôle dédié explicite.

---

## 3. Chiffrement colonne (données médicales)

Au-delà du chiffrement disque managé, les données de santé sensibles sont chiffrées **au niveau applicatif** (module `core/crypto`), avec **une clé par cabinet** dérivée via KMS (Scaleway Key Manager). L'INS est traité comme PII critique.

| Donnée | Traitement |
|---|---|
| INS | Chiffré ; **jamais en clair dans les logs** ; recherche via hash dédié si besoin |
| Contenu `clinical_note` | Chiffré (clé cabinet) |
| Antécédents / allergies / traitements (`medical_record`) | Chiffré |
| Contenu des messages | Chiffré |
| Transcript / résumé Scribe (post-MVP) | Chiffré |
| Documents (Object Storage) | Chiffrés au repos + URLs signées temporaires |

```sql
-- colonnes chiffrées stockées en bytea (ciphertext applicatif), + métadonnée de clé
content_ciphertext bytea NOT NULL,
content_key_ref    text  NOT NULL,   -- référence KMS (version de clé du cabinet)
```

> Le chiffrement est fait **dans l'app** avant écriture, pas par une extension SQL, pour garder la clé hors de la base. Compromis : pas de recherche full-text sur le chiffré (acceptable ; la recherche porte sur des champs non sensibles).

---

## 4. Rétention & soft-delete
- **Soft-delete obligatoire** sur tout le médical : `deleted_at` renseigné, lignes filtrées par défaut (`WHERE deleted_at IS NULL`).
- **Rétention dossier patient** : 20 ans après dernière consultation ; **30 ans pour les mineurs** (compté à partir de la majorité selon la règle applicable).
- **Audit log** : conservé **≥ 10 ans**, append-only.
- **Audio Scribe** (post-MVP) : suppression sous **7 jours** sauf opt-in séparé.
- **Purge** : un job planifié (BullMQ) marque/purge selon politique, en journalisant chaque purge dans l'audit.
- Référence conformité : `07-conformite.md`.

---

## 5. Entités par domaine

### 5.1 Cabinet & identité

```sql
CREATE TABLE cabinet (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raison_sociale text NOT NULL,
  siret         char(14),
  finess        text,
  specialite    text NOT NULL DEFAULT 'dentaire',
  settings      jsonb NOT NULL DEFAULT '{}',   -- horaires, branding, options
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

CREATE TABLE app_user (              -- "user" est réservé : on nomme app_user
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         citext UNIQUE NOT NULL,
  password_hash text,                -- null si auth externe (PSC/FranceConnect, post-MVP)
  mfa_enabled   boolean NOT NULL DEFAULT false,
  mfa_secret    text,
  rpps          text,                -- praticien
  adeli         text,
  status        text NOT NULL DEFAULT 'active',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

CREATE TABLE cabinet_membership (    -- N-N user <-> cabinet, avec rôle
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id  uuid NOT NULL REFERENCES cabinet(id),
  user_id     uuid NOT NULL REFERENCES app_user(id),
  role        text NOT NULL CHECK (role IN ('practitioner','secretary','admin')),
  permissions jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (cabinet_id, user_id)
);

CREATE TABLE practitioner (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id  uuid NOT NULL REFERENCES cabinet(id),
  user_id     uuid NOT NULL REFERENCES app_user(id),
  rpps        text,
  specialite  text,
  conventions jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);
```

### 5.2 Patient & dossier

```sql
CREATE TABLE patient (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  app_user_id     uuid REFERENCES app_user(id),    -- si le patient a un compte app
  ins_ciphertext  bytea,                            -- INS chiffré
  ins_key_ref     text,
  first_name      text NOT NULL,
  last_name       text NOT NULL,
  birth_date      date,
  is_minor        boolean GENERATED ALWAYS AS (birth_date > (current_date - interval '18 years')) STORED,
  contact         jsonb NOT NULL DEFAULT '{}',      -- email, tel, adresse
  mutuelle        jsonb NOT NULL DEFAULT '{}',      -- AMC, no adhérent (champs évolutifs)
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE medical_record (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id    uuid NOT NULL REFERENCES cabinet(id),
  patient_id    uuid NOT NULL REFERENCES patient(id),
  -- antécédents/allergies/traitements chiffrés
  data_ciphertext bytea,
  data_key_ref    text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

CREATE TABLE clinical_note (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  patient_id      uuid NOT NULL REFERENCES patient(id),
  author_id       uuid NOT NULL REFERENCES app_user(id),
  content_ciphertext bytea NOT NULL,
  content_key_ref    text NOT NULL,
  ccam_codes      jsonb NOT NULL DEFAULT '[]',
  scribe_session_id uuid,             -- lien IA (post-MVP)
  validated_at    timestamptz,        -- validation humaine obligatoire
  created_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- spécifique dentaire
CREATE TABLE dental_chart (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id   uuid NOT NULL REFERENCES cabinet(id),
  patient_id   uuid NOT NULL REFERENCES patient(id),
  teeth_status jsonb NOT NULL DEFAULT '{}',  -- status par dent, traitements planifiés
  updated_at   timestamptz NOT NULL DEFAULT now()
);
```

### 5.3 Documents & coffre-fort

```sql
CREATE TABLE document (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id    uuid NOT NULL REFERENCES cabinet(id),
  patient_id    uuid REFERENCES patient(id),
  category      text NOT NULL,        -- devis, facture, ordonnance, radio, cbct, photo, cr, consigne, attestation
  storage_key   text NOT NULL,        -- clé Object Storage (objet chiffré)
  filename      text NOT NULL,
  mime_type     text NOT NULL,
  sha256        char(64) NOT NULL,    -- intégrité
  uploaded_by   uuid REFERENCES app_user(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);
```

### 5.4 Rendez-vous & file d'attente

```sql
CREATE TABLE appointment (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id    uuid NOT NULL REFERENCES cabinet(id),
  patient_id    uuid NOT NULL REFERENCES patient(id),
  practitioner_id uuid NOT NULL REFERENCES practitioner(id),
  starts_at     timestamptz NOT NULL,
  ends_at       timestamptz NOT NULL,
  status        text NOT NULL CHECK (status IN
                  ('requested','confirmed','checked_in','in_progress','done','cancelled','no_show')),
  motif         text,
  pre_checkin   jsonb NOT NULL DEFAULT '{}',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz,
  EXCLUDE USING gist (                         -- pas de double-booking praticien
    practitioner_id WITH =,
    tstzrange(starts_at, ends_at) WITH &&
  ) WHERE (status NOT IN ('cancelled','no_show'))
);

CREATE TABLE checkin_event (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id   uuid NOT NULL REFERENCES cabinet(id),
  appointment_id uuid NOT NULL REFERENCES appointment(id),
  mode         text NOT NULL,    -- qr_app, qr_web, borne, sms
  occurred_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE waiting_list_entry (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id   uuid NOT NULL REFERENCES cabinet(id),
  patient_id   uuid NOT NULL REFERENCES patient(id),
  desired_window jsonb NOT NULL DEFAULT '{}',
  score        numeric(6,2) NOT NULL DEFAULT 0,
  status       text NOT NULL DEFAULT 'active',
  created_at   timestamptz NOT NULL DEFAULT now()
);
```

### 5.5 Devis, signature, facturation

```sql
CREATE TABLE quote (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id    uuid NOT NULL REFERENCES cabinet(id),
  patient_id    uuid NOT NULL REFERENCES patient(id),
  version       int  NOT NULL DEFAULT 1,
  status        text NOT NULL CHECK (status IN ('draft','sent','signed','refused','expired')),
  total_amount  numeric(12,2) NOT NULL DEFAULT 0,
  currency      char(3) NOT NULL DEFAULT 'EUR',
  -- immutabilité une fois signé :
  signed_at     timestamptz,
  signed_sha256 char(64),               -- empreinte du PDF signé
  signature_id  uuid,                   -- -> signature
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

CREATE TABLE quote_item (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id  uuid NOT NULL REFERENCES cabinet(id),
  quote_id    uuid NOT NULL REFERENCES quote(id),
  label       text NOT NULL,
  ccam_code   text,
  tooth       text,                    -- dent concernée (dentaire)
  qty         numeric(6,2) NOT NULL DEFAULT 1,
  unit_amount numeric(12,2) NOT NULL,
  amc_part    numeric(12,2),           -- prise en charge mutuelle estimée
  amo_part    numeric(12,2)            -- part assurance maladie obligatoire
);

CREATE TABLE signature (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id    uuid NOT NULL REFERENCES cabinet(id),
  provider      text NOT NULL DEFAULT 'yousign',
  provider_ref  text NOT NULL,
  level         text NOT NULL DEFAULT 'aes',  -- eIDAS advanced
  certificate   jsonb,                         -- éléments probants
  signed_at     timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE payment_schedule (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id   uuid NOT NULL REFERENCES cabinet(id),
  patient_id   uuid NOT NULL REFERENCES patient(id),
  quote_id     uuid REFERENCES quote(id),
  total_amount numeric(12,2) NOT NULL,
  installments jsonb NOT NULL DEFAULT '[]',  -- jalons multi-dates
  provider     text,                          -- stripe, gocardless, alma(post-MVP)
  status       text NOT NULL DEFAULT 'active',
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE payment (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id    uuid NOT NULL REFERENCES cabinet(id),
  patient_id    uuid NOT NULL REFERENCES patient(id),
  schedule_id   uuid REFERENCES payment_schedule(id),
  quote_id      uuid REFERENCES quote(id),
  amount        numeric(12,2) NOT NULL,
  currency      char(3) NOT NULL DEFAULT 'EUR',
  kind          text NOT NULL,        -- deposit (acompte), installment, full
  provider      text NOT NULL,        -- stripe, gocardless
  provider_ref  text,
  status        text NOT NULL CHECK (status IN ('pending','paid','failed','refunded')),
  idempotency_key text,
  created_at    timestamptz NOT NULL DEFAULT now()
);
```

### 5.6 Messagerie

```sql
CREATE TABLE conversation (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id   uuid NOT NULL REFERENCES cabinet(id),
  patient_id   uuid NOT NULL REFERENCES patient(id),
  scope        text NOT NULL DEFAULT 'patient_cabinet',  -- cloisonnement triadique
  status       text NOT NULL DEFAULT 'open',
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE message (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  conversation_id uuid NOT NULL REFERENCES conversation(id),
  sender_kind     text NOT NULL,     -- patient, secretary, practitioner
  sender_id       uuid,
  body_ciphertext bytea NOT NULL,
  body_key_ref    text NOT NULL,
  triage_flag     text NOT NULL DEFAULT 'normal' CHECK (triage_flag IN ('normal','urgent')),
  triage_reason   text,              -- mots-clés ayant déclenché le flag (traçabilité)
  read_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
```

> **Garde-fou (ADR-009 / `03` §2)** : `triage_flag` est une **priorisation visuelle** issue de règles mots-clés. Aucune décision clinique automatique, aucun routage qui contourne l'humain.

---

## 6. Audit & consentements

```sql
-- append-only, partitionné par mois, rétention >= 10 ans
CREATE TABLE audit_log (
  id           bigint GENERATED ALWAYS AS IDENTITY,
  cabinet_id   uuid NOT NULL,
  actor_id     uuid,
  actor_role   text,
  action       text NOT NULL,        -- read_record, update_quote, sign, login, purge...
  entity       text NOT NULL,
  entity_id    uuid,
  metadata     jsonb NOT NULL DEFAULT '{}',  -- jamais de PII en clair
  occurred_at  timestamptz NOT NULL DEFAULT now()
) PARTITION BY RANGE (occurred_at);
-- pas d'UPDATE/DELETE accordés au rôle applicatif : INSERT seul (append-only)

CREATE TABLE consent_record (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id   uuid NOT NULL REFERENCES cabinet(id),
  patient_id   uuid NOT NULL REFERENCES patient(id),
  purpose      text NOT NULL,        -- soins, ia_scribe(post-MVP), marketing, partage_confrere
  granted      boolean NOT NULL,
  granted_at   timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz,          -- révocable
  evidence     jsonb NOT NULL DEFAULT '{}'
);
```

- **Append-only garanti par privilèges** : le rôle applicatif a `INSERT` mais pas `UPDATE`/`DELETE` sur `audit_log`.
- **Partitioning mensuel** + politique de rétention (10 ans) ; tables anciennes archivées.

---

## 7. Champs JSONB (flexibilité métier sans migration constante)

| Table.colonne | Contenu typique |
|---|---|
| `cabinet.settings` | horaires, branding, options activées, infos pratiques |
| `patient.contact` | email, téléphones, adresse |
| `patient.mutuelle` | AMC, numéro adhérent, plateforme (Almerys/Viamedis) |
| `medical_record` (chiffré) | antécédents, allergies, traitements |
| `dental_chart.teeth_status` | état par dent, plan de traitement |
| `appointment.pre_checkin` | questionnaire J-1, OCR mutuelle, acompte |
| `payment_schedule.installments` | jalons {date, montant, statut} |
| `consent_record.evidence` | trace (horodatage, version CGU, canal) |

> Règle : JSONB pour l'**évolutif non requêté de façon critique**. Tout ce qui sert au filtrage/jointure reste en colonne typée + index.

---

## 8. Index & performance
- Index tenant systématique : `(cabinet_id, ...)` en tête des index composites.
- `appointment` : index `(cabinet_id, practitioner_id, starts_at)` + contrainte d'exclusion anti-double-booking (cf. 5.4).
- `document` : `(cabinet_id, patient_id, category)`.
- `message` : `(conversation_id, created_at)` ; partiel `WHERE triage_flag='urgent'` pour la file d'urgence.
- `quote` : `(cabinet_id, status)`.
- Recherche floue (noms patients) : `pg_trgm` (`GIN` sur champ non sensible) — pas de Meilisearch au MVP.
- `pgvector`/TimescaleDB : **non installés** au MVP (cf. `01` §3.3).

> Diagramme relationnel, contrats d'API et règles métier : voir `04` et `06`. Politiques de rétention détaillées et base légale : `07`.
