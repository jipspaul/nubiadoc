-- 0003_patient_clinical.sql
-- Patient & dossier clinique : patient, medical_record, clinical_note, dental_chart.
-- Réf. : docs/05 §5.2.
-- Chiffrement colonne = applicatif (core/crypto) : on stocke *_ciphertext bytea +
-- *_key_ref text. AUCUN chiffrement fait en SQL (db/README §5).
--
-- NOTE de déviation vs docs/05 (esquisse de référence) : la colonne générée
-- `is_minor GENERATED ALWAYS AS (birth_date > current_date - interval '18 years')`
-- est IMPOSSIBLE en PostgreSQL (current_date n'est pas IMMUTABLE → refus à la
-- création). La minorité se calcule à la volée côté API/vue à partir de birth_date.
-- Signalé à Xav (PROGRESS.md).

CREATE TABLE patient (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  app_user_id     uuid REFERENCES app_user(id),      -- si le patient a un compte app
  ins_ciphertext  bytea,                              -- INS chiffré (applicatif)
  ins_key_ref     text,
  first_name      text NOT NULL,
  last_name       text NOT NULL,
  birth_date      date,
  contact         jsonb NOT NULL DEFAULT '{}',        -- email, tel, adresse
  mutuelle        jsonb NOT NULL DEFAULT '{}',        -- AMC, n° adhérent (évolutif)
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  -- cohérence chiffrement : ciphertext et key_ref vont par paire
  CONSTRAINT patient_ins_crypto_pair CHECK ((ins_ciphertext IS NULL) = (ins_key_ref IS NULL))
);

-- Antécédents / allergies / traitements — chiffré (clé cabinet).
CREATE TABLE medical_record (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  patient_id      uuid NOT NULL REFERENCES patient(id),
  data_ciphertext bytea,
  data_key_ref    text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  CONSTRAINT medical_record_crypto_pair CHECK ((data_ciphertext IS NULL) = (data_key_ref IS NULL))
);

-- Journal clinique (contenu chiffré, validation humaine obligatoire).
CREATE TABLE clinical_note (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id         uuid NOT NULL REFERENCES cabinet(id),
  patient_id         uuid NOT NULL REFERENCES patient(id),
  author_id          uuid NOT NULL REFERENCES app_user(id),
  content_ciphertext bytea NOT NULL,
  content_key_ref    text  NOT NULL,
  ccam_codes         jsonb NOT NULL DEFAULT '[]',
  scribe_session_id  uuid,               -- lien IA (post-MVP)
  validated_at       timestamptz,        -- validation humaine
  created_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz
);

-- Spécifique dentaire : odontogramme.
CREATE TABLE dental_chart (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id   uuid NOT NULL REFERENCES cabinet(id),
  patient_id   uuid NOT NULL REFERENCES patient(id),
  teeth_status jsonb NOT NULL DEFAULT '{}',   -- statut par dent, traitements planifiés
  updated_at   timestamptz NOT NULL DEFAULT now()
);
