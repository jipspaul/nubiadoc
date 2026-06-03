-- 0010_hifi_extensions.sql
-- Deltas issus des maquettes hi-fi. Réf. : docs/05 §10.
-- ⚠️ Périmètre MDR : prescription = affichage passif, AUCUN moteur d'interactions /
--    contre-indications / alternative (docs/07 §8.6). assistant = organisationnel only.

-- 10.1 Couverture santé (niveau plateforme, portable entre cabinets).
ALTER TABLE patient_account
  ADD COLUMN regime_obligatoire text
    CHECK (regime_obligatoire IN ('regime_general','ame','css')),
  ADD COLUMN nss_ciphertext bytea,         -- n° de sécu (PII critique, chiffré applicatif)
  ADD COLUMN nss_key_ref    text,
  ADD COLUMN tiers_payant   boolean NOT NULL DEFAULT false,
  ADD CONSTRAINT patient_account_nss_crypto_pair
    CHECK ((nss_ciphertext IS NULL) = (nss_key_ref IS NULL));

-- 10.2 Proches / ayants droit : un proche est lui-même un patient_account.
CREATE TABLE account_guardianship (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  guardian_account_id  uuid NOT NULL REFERENCES patient_account(id),   -- titulaire gérant
  dependent_account_id uuid NOT NULL REFERENCES patient_account(id),   -- proche géré
  relationship         text NOT NULL CHECK (relationship IN ('enfant','conjoint','parent','autre')),
  authority            text NOT NULL DEFAULT 'legal_guardian',
  active               boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  deleted_at           timestamptz,
  UNIQUE (guardian_account_id, dependent_account_id),
  CONSTRAINT guardianship_not_self CHECK (guardian_account_id <> dependent_account_id)
);

-- 10.3 Journal clinique : type de note + rattachement acte/dent.
ALTER TABLE clinical_note
  ADD COLUMN note_kind text NOT NULL DEFAULT 'session'
    CHECK (note_kind IN ('observation','act','session')),
  ADD COLUMN tooth     text,                          -- FDI (ex. '26') si note_kind='act'
  ADD COLUMN act_ref   jsonb NOT NULL DEFAULT '{}';   -- { label, ccam, quote_item_id? }

-- 10.4 Plan de traitement & phases (au-dessus de quote/quote_item).
CREATE TABLE treatment_plan (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  patient_id      uuid NOT NULL REFERENCES patient(id),
  practitioner_id uuid REFERENCES practitioner(id),
  title           text NOT NULL,
  status          text NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','proposed','accepted','in_progress','done')),
  quote_id        uuid REFERENCES quote(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE treatment_phase (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id uuid NOT NULL REFERENCES cabinet(id),
  plan_id    uuid NOT NULL REFERENCES treatment_plan(id),
  position   int  NOT NULL,
  title      text NOT NULL,                  -- 'Phase 2 · Chirurgie implantaire'
  status     text NOT NULL DEFAULT 'requested'
               CHECK (status IN ('requested','confirmed','in_progress','done'))
);

-- les actes d'une phase = quote_item (déjà : label, ccam_code, tooth, amo/amc) + phase_id
ALTER TABLE quote_item ADD COLUMN phase_id uuid REFERENCES treatment_phase(id);

-- 10.5 Ordonnance / prescription (signature eIDAS + PDF ; AUCUN moteur décisionnel).
CREATE TABLE prescription (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  patient_id      uuid NOT NULL REFERENCES patient(id),
  practitioner_id uuid NOT NULL REFERENCES practitioner(id),
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','signed','sent')),
  signature_id    uuid REFERENCES signature(id),    -- réutilise la brique wedge
  document_id     uuid REFERENCES document(id),      -- PDF → coffre-fort (category='ordonnance')
  signed_at       timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE prescription_item (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  prescription_id uuid NOT NULL REFERENCES prescription(id),
  label           text NOT NULL,            -- 'Paracétamol 1 g'
  form            text,                     -- comprimé, solution…
  posology        text,                     -- '1 cp × 3 / jour si douleur'
  duration        text,                     -- '5 jours'
  quantity        text                      -- QSP '15 cp'
);

-- 10.6 Vérification RPPS/ADELI (ANS). Profil non listé tant que non verified.
CREATE TABLE provider_verification (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES provider(id),
  identifier  text NOT NULL,                -- RPPS ou ADELI soumis
  id_type     text NOT NULL CHECK (id_type IN ('rpps','adeli')),
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','verified','rejected')),
  source      text,                         -- référentiel ANS (annuaire santé)
  checked_at  timestamptz,
  evidence    jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 10.8 Assistant « Demander à Nubia » (post-MVP) : audit/observabilité, organisationnel only.
CREATE TABLE assistant_query (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  actor_id        uuid NOT NULL REFERENCES app_user(id),
  actor_role      text NOT NULL,
  prompt_redacted text,                     -- sans PII
  tools_used      jsonb NOT NULL DEFAULT '[]',
  created_at      timestamptz NOT NULL DEFAULT now()
);
