-- 0009_marketplace.sql
-- Marketplace : compte patient global + annuaire public (géo) + avis. Réf. : docs/05 §9.
-- ⚠️ Entités PLATEFORME hors RLS cabinet : patient_account, profession, specialty,
--    medical_act, establishment, provider (visibilité is_listed), availability_slot,
--    review. Ne PAS leur coller de policy cabinet_id (visibilité dédiée en 0011).

-- Compte patient global (niveau plateforme).
CREATE TABLE patient_account (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_user_id    uuid REFERENCES app_user(id),
  ins_ciphertext bytea,
  ins_key_ref    text,
  first_name     text NOT NULL,
  last_name      text NOT NULL,
  birth_date     date,
  contact        jsonb NOT NULL DEFAULT '{}',
  mutuelle       jsonb NOT NULL DEFAULT '{}',
  created_at     timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz,
  CONSTRAINT patient_account_ins_crypto_pair CHECK ((ins_ciphertext IS NULL) = (ins_key_ref IS NULL))
);

-- Le dossier clinique reste tenant : patient (§5.2) devient le lien cabinet <-> compte.
ALTER TABLE patient ADD COLUMN patient_account_id uuid REFERENCES patient_account(id);

-- Annuaire (lecture publique).
CREATE TABLE profession (
  id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  label text NOT NULL
);

CREATE TABLE specialty (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id uuid REFERENCES profession(id),
  label         text NOT NULL
);

CREATE TABLE medical_act (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  specialty_id uuid REFERENCES specialty(id),
  label        text NOT NULL,
  motifs       text[]
);

CREATE TABLE establishment (
  id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name    text NOT NULL,
  address jsonb NOT NULL DEFAULT '{}',
  geo     geography(Point,4326)        -- PostGIS : "autour de moi"
);

CREATE TABLE provider (                 -- profil PUBLIC du praticien
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  practitioner_id      uuid REFERENCES practitioner(id),
  cabinet_id           uuid REFERENCES cabinet(id),
  establishment_id     uuid REFERENCES establishment(id),
  display_name         text NOT NULL,
  rpps                 text,
  adeli                text,
  rpps_verified        boolean NOT NULL DEFAULT false,
  specialty_id         uuid REFERENCES specialty(id),
  sector               text,           -- conventionnement 1/2/3
  languages            text[],
  pmr                  boolean DEFAULT false,
  teleconsult          boolean DEFAULT false,
  accepts_new_patients boolean DEFAULT true,
  bio                  text,
  photo_key            text,
  geo                  geography(Point,4326),
  rating_avg           numeric(2,1),
  rating_count         int DEFAULT 0,
  is_listed            boolean NOT NULL DEFAULT false   -- listé seulement si rpps_verified
);

CREATE TABLE availability_slot (        -- projection publique des créneaux réservables
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES provider(id),
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  motif       text,
  status      text NOT NULL DEFAULT 'open' CHECK (status IN ('open','held','booked')),
  CONSTRAINT availability_slot_time_order CHECK (ends_at > starts_at)
);

CREATE TABLE review (                    -- avis, rattaché à un vrai RDV, modéré
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id        uuid NOT NULL REFERENCES provider(id),
  patient_account_id uuid NOT NULL REFERENCES patient_account(id),
  appointment_id     uuid REFERENCES appointment(id),
  rating             int CHECK (rating BETWEEN 1 AND 5),
  comment            text,
  status             text NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','published','rejected')),
  created_at         timestamptz NOT NULL DEFAULT now()
);
