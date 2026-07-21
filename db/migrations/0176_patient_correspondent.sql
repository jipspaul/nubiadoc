-- 0176_patient_correspondent.sql
-- Correspondants multiples du patient (#4099) : `patient_referring_doctor`
-- (migration 0129) est UNIQUE par patient_account_id — un seul médecin
-- traitant, aucun support pour plusieurs correspondants (spécialistes,
-- adressage). Nouvelle table à part, `patient_referring_doctor` inchangée
-- (issue : "Ajoute une table", pas de migration de données ni dépréciation).
--
-- Même structure que patient_referring_doctor : soit une référence vers un
-- praticien de l'annuaire (provider), soit une saisie libre (nom+coordonnées)
-- quand le correspondant est hors base Nubia. Entité PLATEFORME (comme
-- patient_coverage, patient_referring_doctor) : RLS patient-scoped par
-- app.patient_account_id.
--
-- Pas de contrainte d'unicité par rôle (ex. un seul 'medecin_traitant') :
-- non demandée par l'issue, qui ne teste que "2 correspondants de rôles
-- différents" — une contrainte plus stricte serait une invention.

CREATE TABLE patient_correspondent (
    id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_account_id uuid        NOT NULL REFERENCES patient_account(id),
    role               text        NOT NULL
                         CHECK (role IN ('medecin_traitant', 'specialiste', 'adressage')),
    provider_id        uuid        REFERENCES provider(id),
    free_name          text,
    free_phone         text,
    free_address       text,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    -- Soit une référence praticien existant, soit une saisie libre (nom obligatoire) — jamais les deux.
    CONSTRAINT patient_correspondent_ref_xor_free CHECK (
        (provider_id IS NOT NULL) <> (free_name IS NOT NULL)
    )
);

CREATE INDEX idx_patient_correspondent_account
    ON patient_correspondent (patient_account_id);

-- RLS patient-scoped : fail-closed (GUC absent → 0 ligne), même pattern que
-- patient_referring_doctor.
ALTER TABLE patient_correspondent ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_correspondent FORCE ROW LEVEL SECURITY;
CREATE POLICY patient_correspondent_owner
    ON patient_correspondent
    FOR ALL
    TO nubia_app
    USING      (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid)
    WITH CHECK (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON patient_correspondent TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON patient_correspondent TO nubia_seed;

COMMENT ON TABLE patient_correspondent IS 'Correspondants médicaux du patient (médecin traitant, spécialistes, adressage) — plusieurs par patient, contrairement à patient_referring_doctor (UNIQUE). Entité plateforme, RLS patient-scoped. Issue #4099.';
