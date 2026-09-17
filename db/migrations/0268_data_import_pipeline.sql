-- 0268_data_import_pipeline.sql
-- #7179 (DP-F14.a) : pipeline de reprise de données (upload, dry-run, run,
-- rapport ligne à ligne). La migration 0168 n'avait posé que la table de
-- suivi `data_import_job` (statut + compteurs) ; cette migration ajoute
-- UNIQUEMENT ce qui manque au pipeline :
--
--   1. `data_import_job` : le fichier source (chiffré par enveloppe sous le
--      cabinet — il peut contenir un INS), son `kind` (parseur), le rapport
--      ligne à ligne (`report jsonb`, produit par le dry-run puis par le
--      run), les compteurs `total_count`/`skipped_count`, l'horodatage du
--      dernier dry-run et l'auteur.
--   2. `patient.external_ref` / `appointment.external_ref` : clé externe
--      (identifiant dans le logiciel source) — pivot d'idempotence : re-jouer
--      le même fichier met à jour au lieu de dupliquer. Unique par cabinet
--      (index partiel, la colonne reste NULL hors reprise).
--
-- Statut : `pending` (fichier reçu) → `running` (run en cours) →
-- `completed` / `failed`. Le dry-run ne change pas le statut (il pose
-- `dry_run_at` + `report`).
--
-- RLS : `data_import_job` est déjà fail-closed (0168) ; `patient` et
-- `appointment` gardent leurs policies (colonne ajoutée seulement).

ALTER TABLE data_import_job
    ADD COLUMN kind               TEXT        NOT NULL DEFAULT 'csv_patients'
        CHECK (kind IN ('csv_patients', 'csv_appointments')),
    ADD COLUMN file_name          TEXT,
    ADD COLUMN payload_ciphertext BYTEA,
    ADD COLUMN payload_key_ref    TEXT,
    ADD COLUMN total_count        INTEGER     NOT NULL DEFAULT 0 CHECK (total_count >= 0),
    ADD COLUMN skipped_count      INTEGER     NOT NULL DEFAULT 0 CHECK (skipped_count >= 0),
    ADD COLUMN dry_run_at         TIMESTAMPTZ,
    ADD COLUMN report             JSONB       NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN created_by         UUID        REFERENCES app_user(id),
    ADD COLUMN created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    ADD CONSTRAINT data_import_job_payload_crypto_pair
        CHECK ((payload_ciphertext IS NULL) = (payload_key_ref IS NULL));

COMMENT ON COLUMN data_import_job.kind IS
    'Parseur (`ImportSource`) : csv_patients | csv_appointments. DSIO à venir (DP-F14.b).';
COMMENT ON COLUMN data_import_job.payload_ciphertext IS
    'Fichier source chiffré par enveloppe (encrypt_column, contexte = cabinet_id) — peut contenir un INS.';
COMMENT ON COLUMN data_import_job.report IS
    'Rapport du dernier dry-run/run : {mode, created, updated, unchanged, errors, lines:[{line, external_ref, action, entity_id?, message?}]}. Jamais de PII au-delà de la clé externe.';

ALTER TABLE patient
    ADD COLUMN external_ref TEXT
        CHECK (external_ref IS NULL OR (btrim(external_ref) <> '' AND length(external_ref) <= 128));

CREATE UNIQUE INDEX idx_patient_cabinet_external_ref
    ON patient (cabinet_id, external_ref)
    WHERE external_ref IS NOT NULL;

COMMENT ON COLUMN patient.external_ref IS
    'Identifiant du patient dans le logiciel source (reprise de données, #7179). Clé d''idempotence par cabinet.';

ALTER TABLE appointment
    ADD COLUMN external_ref TEXT
        CHECK (external_ref IS NULL OR (btrim(external_ref) <> '' AND length(external_ref) <= 128));

CREATE UNIQUE INDEX idx_appointment_cabinet_external_ref
    ON appointment (cabinet_id, external_ref)
    WHERE external_ref IS NOT NULL;

COMMENT ON COLUMN appointment.external_ref IS
    'Identifiant du RDV dans le logiciel source (reprise de données, #7179). Clé d''idempotence par cabinet.';
